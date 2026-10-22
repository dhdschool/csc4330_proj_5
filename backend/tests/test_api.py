import io
import re

import pytest
from gradescopeapi.classes.courses import Course
from PIL import Image

import main
import sessions
from conftest import HAS_FFMPEG, FakeConnection, jpeg_bytes, mov_bytes, png_bytes

SUBMIT = "/courses/1/assignments/2/submit"


# ---------- auth ----------

def test_formats_needs_no_login(client):
    res = client.get("/convert/formats")
    assert res.status_code == 200
    assert "mov" in res.json()["mp4"]
    assert "heic" in res.json()["pdf"]


@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer not-a-real-token"}])
def test_courses_without_valid_token_is_401(client, headers):
    res = client.get("/courses", headers=headers)
    assert res.status_code == 401


def test_login_with_wrong_password_is_401(client, monkeypatch):
    monkeypatch.setattr(sessions, "GSConnection", FakeConnection)
    res = client.post("/auth/login", json={"email": "a@b.edu", "password": "wrong"})
    assert res.status_code == 401
    assert res.json()["detail"] == "Wrong Gradescope email or password"


def test_login_then_logout(client, monkeypatch):
    monkeypatch.setattr(sessions, "GSConnection", FakeConnection)
    res = client.post("/auth/login", json={"email": "a@b.edu", "password": "right"})
    assert res.status_code == 200
    headers = {"Authorization": f"Bearer {res.json()['token']}"}

    assert client.get("/courses", headers=headers).status_code == 200
    assert client.post("/auth/logout", headers=headers).json() == {"ok": True}
    assert client.get("/courses", headers=headers).status_code == 401


def test_each_login_gets_its_own_token(client, monkeypatch):
    monkeypatch.setattr(sessions, "GSConnection", FakeConnection)
    body = {"email": "a@b.edu", "password": "right"}
    first = client.post("/auth/login", json=body).json()["token"]
    second = client.post("/auth/login", json=body).json()["token"]
    assert first != second
    assert main.store.get(first).connection is not main.store.get(second).connection


# ---------- courses & assignments ----------

def test_courses_are_flattened_with_id_and_role(client, login_as):
    course = Course(name="CSC 4330", full_name="Software Systems", semester="Fall",
                    year="2026", num_grades_published=None, num_assignments="5")
    headers = login_as(courses={"student": {"111": course}, "instructor": {"222": course}})

    res = client.get("/courses", headers=headers)
    assert res.status_code == 200
    by_id = {c["id"]: c for c in res.json()}
    assert by_id["111"]["role"] == "student"
    assert by_id["222"]["role"] == "instructor"
    assert by_id["111"]["name"] == "CSC 4330"


def test_gradescope_failure_is_502(client, auth, monkeypatch):
    def broken():
        raise RuntimeError("page layout changed")

    main.store.get("test-token").connection.account.get_courses = broken
    res = client.get("/courses", headers=auth)
    assert res.status_code == 502


# ---------- conversion ----------

def test_convert_png_to_jpg(client, auth):
    res = client.post("/convert", headers=auth,
                      files={"file": ("photo.png", png_bytes())}, data={"target": "jpg"})
    assert res.status_code == 200
    assert res.content[:3] == b"\xff\xd8\xff"  # JPEG signature
    assert "photo.jpg" in res.headers["content-disposition"]


def test_unsupported_conversion_is_400(client, auth):
    res = client.post("/convert", headers=auth,
                      files={"file": ("photo.png", png_bytes())}, data={"target": "mp4"})
    assert res.status_code == 400
    assert "Can't convert .png to .mp4" in res.json()["detail"]


def test_convert_turns_phone_photos_upright(client, auth):
    exif = Image.Exif()
    exif[0x0112] = 6  # Orientation: shown rotated 90°, as phone cameras save portrait shots
    res = client.post("/convert", headers=auth, data={"target": "png"},
                      files={"file": ("portrait.jpg", jpeg_bytes(size=(40, 30), exif=exif))})
    assert res.status_code == 200
    assert Image.open(io.BytesIO(res.content)).size == (30, 40)


def test_convert_puts_transparency_on_white(client, auth):
    buf = io.BytesIO()
    Image.new("RGBA", (10, 10), (0, 0, 0, 0)).save(buf, "PNG")
    res = client.post("/convert", headers=auth, data={"target": "jpg"},
                      files={"file": ("ink.png", buf.getvalue())})
    assert res.status_code == 200
    assert min(Image.open(io.BytesIO(res.content)).getpixel((5, 5))) > 245  # white, not black


def test_convert_needs_login(client):
    res = client.post("/convert", files={"file": ("photo.png", png_bytes())},
                      data={"target": "jpg"})
    assert res.status_code == 401


@pytest.mark.skipif(not HAS_FFMPEG, reason="ffmpeg is not installed")
def test_convert_mov_to_mp4(client, auth, tmp_path):
    res = client.post("/convert", headers=auth,
                      files={"file": ("clip.mov", mov_bytes(tmp_path))}, data={"target": "mp4"})
    assert res.status_code == 200
    assert res.content[4:8] == b"ftyp"  # MP4 container signature


# ---------- submission ----------

def test_submit_files_as_they_are(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth, files=[("files", ("hw1.png", png_bytes()))])
    assert res.status_code == 200
    assert res.json() == {"submission_url": fake_upload.result, "files": ["hw1.png"]}
    assert fake_upload.file_names == ["hw1.png"]


def test_two_images_combine_into_one_pdf(client, auth, fake_upload):
    res = client.post(
        SUBMIT, headers=auth,
        files=[("files", ("page1.png", png_bytes("red"))),
               ("files", ("page2.png", png_bytes("blue")))],
        data={"combine_images_to_pdf": "true"},
    )
    assert res.status_code == 200
    assert fake_upload.file_names == ["submission.pdf"]
    pdf = fake_upload.contents[0]
    assert pdf.startswith(b"%PDF")
    assert len(re.findall(rb"/Type\s*/Page(?!s)", pdf)) == 2  # one page per image


def test_same_file_name_is_kept_apart(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth, files=[("files", ("a.png", png_bytes()))] * 3)
    assert res.status_code == 200
    assert fake_upload.file_names == ["a.png", "a_1.png", "a_2.png"]


def test_converting_does_not_overwrite_an_uploaded_file(client, auth, fake_upload):
    original = jpeg_bytes()
    res = client.post(SUBMIT, headers=auth, data={"convert_to": "jpg"},
                      files=[("files", ("photo.png", png_bytes())),
                             ("files", ("photo.jpg", original))])
    assert res.status_code == 200
    assert fake_upload.file_names == ["photo_1.jpg", "photo.jpg"]
    assert fake_upload.contents[1] == original


@pytest.mark.skipif(not HAS_FFMPEG, reason="ffmpeg is not installed")
def test_submit_mov_converted_to_mp4(client, auth, fake_upload, tmp_path):
    res = client.post(SUBMIT, headers=auth,
                      files=[("files", ("clip.mov", mov_bytes(tmp_path)))],
                      data={"convert_to": "mp4"})
    assert res.status_code == 200
    assert fake_upload.file_names == ["clip.mp4"]


def test_bad_conversion_on_submit_is_400_and_nothing_uploaded(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth, files=[("files", ("notes.txt", b"hello"))],
                      data={"convert_to": "pdf"})
    assert res.status_code == 400
    assert fake_upload.file_names is None


def test_rejected_submission_is_400(client, auth, fake_upload):
    fake_upload.result = None  # what the library returns when Gradescope says no
    res = client.post(SUBMIT, headers=auth, files=[("files", ("hw1.png", png_bytes()))])
    assert res.status_code == 400
    assert "Gradescope rejected the submission" in res.json()["detail"]


def test_file_over_size_limit_is_413(client, auth, fake_upload, monkeypatch):
    monkeypatch.setattr(main, "MAX_UPLOAD_BYTES", 100)
    res = client.post(SUBMIT, headers=auth, files=[("files", ("big.png", png_bytes(size=(400, 400))))])
    assert res.status_code == 413
    assert fake_upload.file_names is None


def test_submit_needs_login(client, fake_upload):
    res = client.post(SUBMIT, files=[("files", ("hw1.png", png_bytes()))])
    assert res.status_code == 401
    assert fake_upload.file_names is None


def test_unsafe_file_name_is_cleaned(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth,
                      files=[("files", ("../../etc/hw 1?.png", png_bytes()))])
    assert res.status_code == 200
    assert fake_upload.file_names == ["hw 1_.png"]


def test_long_file_name_keeps_its_extension(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth, files=[("files", ("x" * 200 + ".png", png_bytes()))])
    assert res.status_code == 200
    assert fake_upload.file_names == ["x" * 100 + ".png"]


def test_unreadable_image_is_400(client, auth, fake_upload):
    res = client.post(SUBMIT, headers=auth, data={"combine_images_to_pdf": "true"},
                      files=[("files", ("scan.png", b"not really a png"))])
    assert res.status_code == 400
    assert "scan.png is not a readable image" in res.json()["detail"]
    assert fake_upload.file_names is None
