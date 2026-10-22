"""Shared fixtures. Nothing here talks to the real Gradescope.

Logged-in tests put a fake session straight into the server's session store, and
uploads go to a stand-in for gradescopeapi's upload_assignment.
"""

import io
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))  # backend/

import main  # noqa: E402
from sessions import UserSession  # noqa: E402

TOKEN = "test-token"
HAS_FFMPEG = shutil.which("ffmpeg") is not None


class FakeConnection:
    """Stands in for gradescopeapi's GSConnection."""

    def __init__(self, courses=None, assignments=None):
        self.session = object()  # passed through to upload_assignment untouched
        self.account = SimpleNamespace(
            get_courses=lambda: courses or {"student": {}, "instructor": {}},
            get_assignments=lambda course_id: assignments or [],
        )

    def login(self, email, password):
        if password != "right":
            raise ValueError("Invalid credentials.")

    def logout(self):
        pass


@pytest.fixture
def client():
    yield TestClient(main.app)
    main.store._sessions.clear()


@pytest.fixture
def login_as(client):
    """Log in with a fake connection; returns the auth header."""

    def _login(**connection_kwargs):
        main.store._sessions[TOKEN] = UserSession(
            connection=FakeConnection(**connection_kwargs), email="student@example.com"
        )
        return {"Authorization": f"Bearer {TOKEN}"}

    return _login


@pytest.fixture
def auth(login_as):
    return login_as()


@pytest.fixture
def fake_upload(monkeypatch):
    """Replaces the Gradescope upload. Set .result to change what it returns."""
    calls = SimpleNamespace(result="https://www.gradescope.com/courses/1/assignments/2/submissions/3",
                            file_names=None, contents=None)

    def upload(session, course_id, assignment_id, *files, leaderboard_name=None):
        calls.file_names = [Path(f.name).name for f in files]
        calls.contents = [f.read() for f in files]
        return calls.result

    monkeypatch.setattr(main, "upload_assignment", upload)
    return calls


def png_bytes(color="red", size=(40, 30)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "PNG")
    return buf.getvalue()


def jpeg_bytes(color="blue", size=(40, 30), exif=None) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, "JPEG", exif=exif or Image.Exif())
    return buf.getvalue()


def mov_bytes(tmp_path: Path) -> bytes:
    """A one-second test video, made with ffmpeg."""
    out = tmp_path / "clip.mov"
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
         "testsrc=duration=1:size=64x48:rate=10", "-pix_fmt", "yuv420p", str(out)],
        check=True,
    )
    return out.read_bytes()
