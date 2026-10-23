"""Parsing an assignment's questions out of Gradescope's pages. No network: the
pages are tiny stand-ins carrying the same React props Gradescope embeds."""

import html
import json
from types import SimpleNamespace

import pytest
from bs4 import BeautifulSoup
from gradescopeapi.classes._helpers._assignment_helpers import check_page_auth, get_content
from gradescopeapi.classes.content import (
    AssignmentSubmissionContent,
    Content,
    OnlineAssignmentSubmitterContent,
    RadioInput,
    TextContent,
    UnknownContent,
)

QUESTION = {
    "id": 11, "title": "Pick one", "index": 1, "weight": "2.0", "scoring_type": "positive",
    "content": [
        {"type": "text", "value": "Which sort is stable?"},
        {"type": "radio_input", "choices": [{"value": "Merge sort"}, {"value": "Heap sort"}]},
    ],
}

NEW_SUBMISSION = {  # props of the page for answering an online assignment
    "title": "Quiz 1",
    "outline": [{**QUESTION, "type": "OnlineQuestion", "parent_id": None}],
    "outlineHash": "abc123",
    "answers": {},
    "questionSubmissions": {},
    "files": [],
}

SUBMITTED = {  # props of the page for viewing a submission
    "assignment": {"id": 5, "title": "Quiz 1", "total_points": "2.0", "student_submission": True,
                   "due_date": "2026-10-30T23:59:00.000-05:00", "submission_allowed": True},
    "assignment_submission": {"id": 9, "created_at": "2026-10-22T13:00:00.000-05:00"},
    "question_submissions": [
        {"id": 3, "question_id": 11, "data": {}, "active": True, "answers": {"0": "Merge sort"}},
    ],
    "questions": [QUESTION],
    "text_files": [],
}


def page(react_class: str, props: dict) -> BeautifulSoup:
    props_attr = html.escape(json.dumps(props))
    return BeautifulSoup(
        f'<html><body><div data-react-class="{react_class}" data-react-props="{props_attr}">'
        "</div></body></html>",
        "html.parser",
    )


def test_new_submission_page():
    content = get_content(page("OnlineAssignmentSubmitter", NEW_SUBMISSION)).content
    assert isinstance(content, OnlineAssignmentSubmitterContent)
    text, radio = content.outline[0].content
    assert isinstance(text, TextContent) and text.value == "Which sort is stable?"
    assert isinstance(radio, RadioInput)
    assert [c.value for c in radio.choices] == ["Merge sort", "Heap sort"]


def test_new_submission_page_without_attached_files():
    # Gradescope sends null rather than [] when the assignment has no files
    content = get_content(page("OnlineAssignmentSubmitter", {**NEW_SUBMISSION, "files": None})).content
    assert content.files is None
    assert content.outline[0].title == "Pick one"


def test_submitted_page():
    content = get_content(page("AssignmentSubmissionViewer", SUBMITTED)).content
    assert isinstance(content, AssignmentSubmissionContent)
    assert content.assignment.title == "Quiz 1"
    assert content.question_submissions[0].answers == {"0": "Merge sort"}


def test_unmodelled_content_type_is_kept_instead_of_failing():
    image = {"type": "image", "url": "https://example.com/graph.png", "alt": "A graph"}
    question = {**QUESTION, "content": [*QUESTION["content"], image]}
    props = {**NEW_SUBMISSION, "outline": [{**NEW_SUBMISSION["outline"][0], **question}]}

    blocks = get_content(page("OnlineAssignmentSubmitter", props)).content.outline[0].content
    assert isinstance(blocks[1], RadioInput)  # known types are still parsed fully
    assert isinstance(blocks[2], UnknownContent)
    assert blocks[2].type == "image"
    assert blocks[2].model_dump() == image  # nothing lost


def test_bad_known_content_is_still_an_error():
    question = {**QUESTION, "content": [{"type": "radio_input"}]}  # no choices
    props = {**NEW_SUBMISSION, "outline": [{**NEW_SUBMISSION["outline"][0], **question}]}
    with pytest.raises(ValueError, match="choices"):
        get_content(page("OnlineAssignmentSubmitter", props))


def test_content_round_trips_through_json():
    for react_class, props in [("OnlineAssignmentSubmitter", NEW_SUBMISSION),
                               ("AssignmentSubmissionViewer", SUBMITTED)]:
        content = get_content(page(react_class, props))
        assert Content.model_validate_json(content.model_dump_json()) == content


def test_page_without_an_online_assignment():
    with pytest.raises(ValueError, match="Could not get content"):
        get_content(BeautifulSoup("<html><body>Log in</body></html>", "html.parser"))


@pytest.mark.parametrize("status", [403, 500, 503])
def test_unexpected_status_is_an_error_not_none(status):
    session = SimpleNamespace(get=lambda url: SimpleNamespace(status_code=status, text=""))
    with pytest.raises(Exception, match=str(status)):
        check_page_auth(session, "https://www.gradescope.com/courses/1/assignments/2")
