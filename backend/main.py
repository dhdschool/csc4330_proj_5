"""Backend for the Gradescope uploader app.

Run:  uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
Docs: http://localhost:8000/docs

Every endpoint except /auth/login needs the header:
    Authorization: Bearer <token from /auth/login>
"""

import dataclasses
import os
import re
import shutil
import tempfile
from contextlib import ExitStack
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from starlette.background import BackgroundTask

from gradescopeapi.classes.upload import upload_assignment

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
