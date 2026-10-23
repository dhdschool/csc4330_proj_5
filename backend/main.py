"""Backend for the Gradescope uploader app.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
Docs: http://localhost:8000/docs

Every endpoint except /auth/login needs the header:
    Authorization: Bearer <token from /auth/login>
"""

import dataclasses
import json
import os
import re
import shutil
import tempfile
from contextlib import ExitStack
from pathlib import Path
from urllib.parse import urlparse

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, ValidationError
from starlette.background import BackgroundTask

from gradescopeapi import DEFAULT_GRADESCOPE_BASE_URL
from gradescopeapi.classes._helpers._assignment_helpers import NotAuthorized
from gradescopeapi.classes.content import OnlineAssignmentSubmitterContent
from gradescopeapi.classes.upload import save_online_answers, upload_assignment

import converter
from sessions import SessionStore, UserSession

MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_MB", "500")) * 1024 * 1024
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")

app = FastAPI(title="Gradescope Uploader API")
app.add_middleware(
    CORSMiddleware,  # needed for the Flutter *web* build
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)
store = SessionStore()


# ---------- auth ----------

class LoginRequest(BaseModel):
    email: str
    password: str


def current_session(authorization: str = Header(default="")) -> UserSession:
    token = authorization.removeprefix("Bearer ").strip()
    session = store.get(token) if token else None
    if not session:
        raise HTTPException(401, "Not logged in or session expired")
    return session


@app.post("/auth/login")
def login(body: LoginRequest):
    try:
        token = store.create(body.email, body.password)
    except ValueError:
        raise HTTPException(401, "Wrong Gradescope email or password")
    except Exception as e:
        raise HTTPException(502, f"Couldn't reach Gradescope: {e}")
    return {"token": token}


@app.post("/auth/logout")
def logout(authorization: str = Header(default="")):
    store.delete(authorization.removeprefix("Bearer ").strip())
    return {"ok": True}


# ---------- courses & assignments ----------

@app.get("/courses")
def courses(s: UserSession = Depends(current_session)):
    try:
        data = s.connection.account.get_courses()
    except Exception as e:
        raise HTTPException(502, f"Failed to load courses: {e}")
    # Flatten {"student": {id: Course}, "instructor": {...}} into one list
    return [
        {"id": course_id, "role": role, **dataclasses.asdict(course)}
        for role, by_id in data.items()
        for course_id, course in by_id.items()
    ]


@app.get("/courses/{course_id}/assignments")
def assignments(course_id: str, s: UserSession = Depends(current_session)):
    try:
        items = s.connection.account.get_assignments(course_id)
    except Exception as e:
        raise HTTPException(502, f"Failed to load assignments: {e}")
    return [dataclasses.asdict(a) for a in items]


@app.get("/courses/{course_id}/assignments/{assignment_id}/content")
def assignment_content(course_id: str, assignment_id: str, s: UserSession = Depends(current_session)):
    """The assignment's questions, in order, with what's already been submitted.

    - answers: {"<question id>/<input number>": text or chosen option}
    - files: {"<question id>/<input number>": [file names already uploaded]}
    - submission: the latest submission (id, created_at, score, total_points, url), or null

    Only online assignments have questions on Gradescope; upload-only ones
    have none, so their list is empty.
    """
    try:
        content = s.connection.account.get_assignment_content(course_id, assignment_id).content
    except NotAuthorized:
        raise HTTPException(403, "You don't have access to this assignment")
    except ValidationError as e:  # before ValueError: it's a subclass
        print(f"Unreadable content for assignment {assignment_id}:\n{e}")  # every field, for fixing content.py
        first = e.errors()[0]
        where = ".".join(str(part) for part in first["loc"])
        raise HTTPException(
            502,
            f"Couldn't read the assignment from Gradescope ({e.error_count()} unexpected fields, "
            f"first at {where}: {first['msg']}, got {first.get('input')!r:.80})",
        )
    except ValueError:  # no questions on the page
        return {"questions": [], "answers": {}, "files": {}, "submission": None}
    except Exception as e:
        raise HTTPException(502, f"Failed to load assignment: {e}")

    # A new submission lists its questions as an "outline", a submitted one as "questions"
    if isinstance(content, OnlineAssignmentSubmitterContent):
        questions, saved, submission = content.outline, content.answers, None
    else:
        questions = content.questions
        saved = {str(qs.question_id): qs.answers for qs in content.question_submissions if qs.active}
        sub = content.assignment_submission
        submission = sub and {
            "id": sub.id,
            "created_at": sub.created_at and sub.created_at.isoformat(),
            "score": sub.score,
            "total_points": content.assignment.total_points,
            "url": f"{DEFAULT_GRADESCOPE_BASE_URL}/courses/{course_id}/assignments/{assignment_id}/submissions/{sub.id}",
        }

    answers, files = {}, {}
    for question_id, inputs in saved.items():
        for number, value in (inputs or {}).items():
            key = f"{question_id}/{number}"
            if isinstance(value, str):
                answers[key] = value
            elif isinstance(value, list) and (names := [n for v in value if (n := _file_name(v))]):
                files[key] = names

    return {
        "questions": [
            {
                **q.model_dump(mode="json", include={"id", "title", "index", "weight", "content"}),
                "parent_id": getattr(q, "parent_id", None),
            }
            for q in questions
        ],
        "answers": answers,
        "files": files,
        "submission": submission,
    }


def _file_name(saved) -> str | None:
    """Name of a file in a saved file-upload answer. We haven't seen one from
    Gradescope yet, so accept the likely shapes: a name, a URL, or a dict."""
    if isinstance(saved, str):
        return Path(urlparse(saved).path).name or None
    if isinstance(saved, dict):
        for key in ("filename", "file_name", "original_filename", "name"):
            if isinstance(saved.get(key), str):
                return saved[key]
        for key in ("path", "url", "file"):
            if saved.get(key):
                return _file_name(saved[key])
    return None


@app.post("/courses/{course_id}/assignments/{assignment_id}/answers")
def save_answers(
    course_id: str,
    assignment_id: str,
    answers: str = Form("{}"),  # JSON {"<question id>/<input number>": typed text}
    choices: str = Form("{}"),  # JSON {"<question id>/<input number>": chosen option's text}
    files: list[UploadFile] = File(default=[]),  # filename "<question id>/<input number>/<name>"
    conversions: str = Form("{}"),  # JSON {"<question id>/<input number>": "none" | "combine" | "to:<ext>"}
    s: UserSession = Depends(current_session),
):
    """Answer an online assignment's questions, converting each upload's files first if asked."""
    try:
        typed, chosen, convert = json.loads(answers), json.loads(choices), json.loads(conversions)
    except json.JSONDecodeError:
        raise HTTPException(400, "answers, choices and conversions must be JSON")

    by_question: dict[str, dict[str, str]] = {}
    for key, value in {**typed, **chosen}.items():
        question_id, _, number = key.partition("/")
        by_question.setdefault(question_id, {})[number] = str(value)

    work = Path(tempfile.mkdtemp())
    try:
        # Each upload input gets its own folder, so two inputs' files never collide
        saved: dict[str, list[Path]] = {}
        for f in files:
            key = (f.filename or "").rsplit("/", 1)[0]
            if key.count("/") != 1:
                raise HTTPException(400, f"Don't know which question {f.filename} answers")
            folder = work / key.replace("/", "_")
            folder.mkdir(exist_ok=True)
            saved.setdefault(key, []).append(_save_upload(f, folder))

        file_answers: dict[str, dict[str, list[Path]]] = {}
        for key, paths in saved.items():
            question_id, _, number = key.partition("/")
            converted = _apply_conversion(paths, convert.get(key, "none"), work / key.replace("/", "_"))
            file_answers.setdefault(question_id, {})[number] = converted

        if not by_question and not file_answers:
            return {"saved": 0, "files": []}
        with ExitStack() as stack:
            handles = {
                question_id: {n: [stack.enter_context(open(p, "rb")) for p in paths] for n, paths in inputs.items()}
                for question_id, inputs in file_answers.items()
            }
            save_online_answers(s.connection.session, course_id, assignment_id, by_question, handles)
    except converter.ConversionError as e:
        raise HTTPException(400, str(e))
    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        raise HTTPException(502, f"Saving to Gradescope failed: {e}")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    return {
        "saved": sum(len(v) for v in by_question.values()),
        "files": [p.name for inputs in file_answers.values() for paths in inputs.values() for p in paths],
    }


# ---------- conversion ----------

@app.get("/convert/formats")
def formats():
    """Which source extensions can become which target format."""
    return {target: sorted(src) for target, src in converter.SUPPORTED.items()}


@app.post("/convert")
def convert_file(
    file: UploadFile = File(...),
    target: str = Form(...),
    s: UserSession = Depends(current_session),  # only logged-in users may convert
):
    """Convert one file and send it back (lets the app preview before submitting)."""
    work = Path(tempfile.mkdtemp())
    try:
        src = _save_upload(file, work)
        out = converter.convert(src, target, work)
    except converter.ConversionError as e:
        shutil.rmtree(work, ignore_errors=True)
        raise HTTPException(400, str(e))
    except Exception:
        shutil.rmtree(work, ignore_errors=True)
        raise
    return FileResponse(
        out,
        filename=out.name,
        background=BackgroundTask(shutil.rmtree, work, ignore_errors=True),
    )


# ---------- submission ----------

@app.post("/courses/{course_id}/assignments/{assignment_id}/submit")
def submit(
    course_id: str,
    assignment_id: str,
    files: list[UploadFile] = File(...),
    convert_to: str | None = Form(None),
    combine_images_to_pdf: bool = Form(False),
    leaderboard_name: str | None = Form(None),
    s: UserSession = Depends(current_session),
):
    """Upload files to a Gradescope assignment, converting first if asked.

    - convert_to: e.g. "mp4" converts every file that isn't already mp4.
    - combine_images_to_pdf: merge all uploaded images (in the order sent)
      into one PDF, for "upload a PDF" assignments.
    """
    work = Path(tempfile.mkdtemp())
    try:
        saved = [_save_upload(f, work) for f in files]

        if combine_images_to_pdf:
            to_send = [converter.images_to_pdf(saved, work / "submission.pdf")]
        elif convert_to:
            to_send = [converter.convert(p, convert_to, work) for p in saved]
        else:
            to_send = saved

        with ExitStack() as stack:
            handles = [stack.enter_context(open(p, "rb")) for p in to_send]
            link = upload_assignment(
                s.connection.session,
                course_id,
                assignment_id,
                *handles,
                leaderboard_name=leaderboard_name,
            )
    except converter.ConversionError as e:
        raise HTTPException(400, str(e))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(502, f"Upload to Gradescope failed: {e}")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if not link:
        # Gradescope returns 200 even on failure; the library detects it by the redirect.
        raise HTTPException(
            400,
            "Gradescope rejected the submission (past due, wrong file type, "
            "or the assignment doesn't accept uploads)",
        )
    return {"submission_url": link, "files": [p.name for p in to_send]}


# ---------- helpers ----------

def _safe_name(name: str) -> str:
    name = re.sub(r"[^A-Za-z0-9._ -]", "_", Path(name or "file").name)
    stem, suffix = os.path.splitext(name)
    return stem[:100] + suffix[:20] or "file"  # shorten without losing the extension


def _apply_conversion(paths: list[Path], conversion: str, dest_dir: Path) -> list[Path]:
    """Applies a conversion picked in the app: "none", "combine" or "to:<ext>"."""
    if conversion == "none":
        return paths
    if conversion == "combine":
        return [converter.images_to_pdf(paths, converter.unique_path(dest_dir / "submission.pdf"))]
    if conversion.startswith("to:"):
        return [converter.convert(p, conversion[3:], dest_dir) for p in paths]
    raise HTTPException(400, f"Unknown conversion {conversion!r}")


def _save_upload(upload: UploadFile, dest_dir: Path) -> Path:
    """Stream an upload to disk, enforcing the size limit."""
    path = converter.unique_path(dest_dir / _safe_name(upload.filename))  # two files with the same name
    written = 0
    with open(path, "wb") as out:
        while chunk := upload.file.read(1024 * 1024):
            written += len(chunk)
            if written > MAX_UPLOAD_BYTES:
                raise HTTPException(413, f"{upload.filename} is over {MAX_UPLOAD_BYTES // 2**20} MB")
            out.write(chunk)
    return path
