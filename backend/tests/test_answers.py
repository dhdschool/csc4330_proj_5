"""Saving answers to an online assignment. No network: a fake session stands in
for Gradescope and records what the app would have sent."""

import html
import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from gradescopeapi.classes.upload import save_online_answers

import main
from conftest import png_bytes

ANSWERS = "/courses/1/assignments/2/answers"

PROPS = {  # the parts of OnlineAssignmentSubmitter's props that saving reads
    "outlineHash": "52614903ee",
    "answers": {"78571505": {"5": "3", "6": [{"id": 1, "name": "old.png"}]}},
    "assignment": {"id": 2, "owner_id": 7655670},
}


class FakeGradescope:
    def __init__(self, props=PROPS, status=200):
        self.props, self.status, self.posted = props, status, None

    def get(self, url):
        props = "" if self.props is None else html.escape(json.dumps(self.props))
        view = (f'<div data-react-class="OnlineAssignmentSubmitter" data-react-props="{props}"></div>'
                if self.props is not None else "")
        page = f'<html><head><meta name="csrf-token" content="tok"></head><body>{view}</body></html>'
        return SimpleNamespace(text=page, status_code=200, url=url)

    def post(self, url, data, headers):
        self.posted = SimpleNamespace(url=url, fields=dict(data.fields), headers=headers)
        return SimpleNamespace(status_code=self.status)


def test_sends_what_the_save_answer_button_sends():
    gs = FakeGradescope()
    save_online_answers(gs, "1", "2", {"78571505": {"0": "https://github.com/me/app"}})

    assert gs.posted.url.endswith("/courses/1/assignments/2/submissions")
    assert gs.posted.headers["X-CSRF-Token"] == "tok"
    assert gs.posted.fields["owner_id"] == "7655670"
    assert gs.posted.fields["outline_hash"] == "52614903ee"
    # Text and choices already saved for that question are sent back unchanged;
    # files already uploaded aren't
    assert json.loads(gs.posted.fields["questions"]) == {
        "78571505": {"0": "https://github.com/me/app", "5": "3"}
    }


def test_files_go_in_their_own_field_per_input(tmp_path):
    (tmp_path / "tasks.png").write_bytes(b"png")
    gs = FakeGradescope()
    with open(tmp_path / "tasks.png", "rb") as f:
        save_online_answers(gs, "1", "2", {"78571505": {"1": "1"}}, {"78571505": {"6": [f]}})

    name, _, mimetype = gs.posted.fields["assignment_submission_files[78571505][6][]"]
    assert (name, mimetype) == ("tasks.png", "image/png")
    assert json.loads(gs.posted.fields["questions"])["78571505"]["1"] == "1"


def test_closed_assignment_is_refused():
    with pytest.raises(ValueError, match="isn't open"):
        save_online_answers(FakeGradescope(props=None), "1", "2", {"1": {"0": "x"}})


def test_missing_owner_id_says_what_the_page_has():
    gs = FakeGradescope(props={"outlineHash": "h", "answers": {}})
    with pytest.raises(ValueError, match="answers, outlineHash"):
        save_online_answers(gs, "1", "2", {"1": {"0": "x"}})
    assert gs.posted is None


def test_gradescope_refusing_is_an_error():
    with pytest.raises(ValueError, match="422"):
        save_online_answers(FakeGradescope(status=422), "1", "2", {"1": {"0": "x"}})


# ---------- the endpoint ----------

@pytest.fixture
def fake_save(monkeypatch):
    """Replaces the Gradescope save; records answers and {qid: {input: [(name, bytes)]}}."""
    calls = []

    def save(session, course_id, assignment_id, answers, files):
        calls.append(SimpleNamespace(answers=answers, files={
            qid: {n: [(Path(f.name).name, f.read()) for f in handles] for n, handles in inputs.items()}
            for qid, inputs in files.items()
        }))

    monkeypatch.setattr(main, "save_online_answers", save)
    return calls


def test_typed_answers_and_choices_are_grouped_by_question(client, auth, fake_save):
    res = client.post(ANSWERS, headers=auth, data={
        "answers": json.dumps({"78571505/0": "url", "78571505/2": "other"}),
        "choices": json.dumps({"78571505/1": "8+"}),
    })
    assert res.status_code == 200
    [call] = fake_save
    assert call.answers == {"78571505": {"0": "url", "1": "8+", "2": "other"}}
    assert call.files == {}


def test_each_upload_gets_its_own_conversion(client, auth, fake_save):
    res = client.post(ANSWERS, headers=auth, data={
        "conversions": json.dumps({"7/6": "combine", "7/7": "none"}),
    }, files=[
        ("files", ("7/6/page1.png", png_bytes("red"))),
        ("files", ("7/6/page2.png", png_bytes("blue"))),
        ("files", ("7/7/demo.mp4", b"video")),
    ])
    assert res.status_code == 200
    files = fake_save[0].files["7"]
    assert [name for name, _ in files["6"]] == ["submission.pdf"]
    assert files["6"][0][1].startswith(b"%PDF")
    assert files["7"] == [("demo.mp4", b"video")]


def test_bad_conversion_is_400_and_nothing_saved(client, auth, fake_save):
    res = client.post(ANSWERS, headers=auth, data={"conversions": json.dumps({"7/6": "combine"})},
                      files=[("files", ("7/6/notes.txt", b"not an image"))])
    assert res.status_code == 400
    assert fake_save == []


def test_nothing_to_save_skips_gradescope(client, auth, fake_save):
    res = client.post(ANSWERS, headers=auth, data={})
    assert res.json() == {"saved": 0, "files": []}
    assert fake_save == []


def test_gradescope_refusal_is_400(client, auth, monkeypatch):
    def refuse(*args):
        raise ValueError("This assignment isn't open for answering (it may be closed)")

    monkeypatch.setattr(main, "save_online_answers", refuse)
    res = client.post(ANSWERS, headers=auth, data={"answers": json.dumps({"7/0": "url"})})
    assert res.status_code == 400
    assert "isn't open" in res.json()["detail"]


def test_answers_need_login(client, fake_save):
    assert client.post(ANSWERS, data={"answers": "{}"}).status_code == 401
