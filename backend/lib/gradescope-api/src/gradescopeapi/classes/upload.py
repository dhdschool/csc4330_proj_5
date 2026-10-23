"""Functions for uploading assignments to Gradescope."""

import io
import json
import mimetypes
import pathlib

import requests
from bs4 import BeautifulSoup
from requests_toolbelt.multipart.encoder import MultipartEncoder

from gradescopeapi import DEFAULT_GRADESCOPE_BASE_URL


def upload_assignment(
    session: requests.Session,
    course_id: str,
    assignment_id: str,
    *files: io.TextIOWrapper,
    leaderboard_name: str | None = None,
    gradescope_base_url: str = DEFAULT_GRADESCOPE_BASE_URL,
) -> str | None:
    """Uploads given file objects to the specified assignment on Gradescope.

    Args:
        session (requests.Session): The session object to use for making HTTP requests.
        course_id (str): The ID of the course on Gradescope.
        assignment_id (str): The ID of the assignment on Gradescope.
        *files (io.TextIOWrapper): Variable number of file objects to upload.
        leaderboard_name (str | None, optional): The name of the leaderboard. Defaults to None.

    Returns:
        str | None: Link to submission if successful or None if unsuccessful.
    """
    GS_COURSE_ENDPOINT = f"{gradescope_base_url}/courses/{course_id}"
    GS_UPLOAD_ENDPOINT = f"{gradescope_base_url}/courses/{course_id}/assignments/{assignment_id}/submissions"

    # Get auth token
    # TODO: Refactor to helper function since it is needed in multiple places
    response = session.get(GS_COURSE_ENDPOINT)
    soup = BeautifulSoup(response.text, "html.parser")
    auth_token = soup.find("meta", {"name": "csrf-token"})["content"]

    # Format files for upload
    form_files = []
    for file in files:
        form_files.append(
            (
                "submission[files][]",
                (
                    pathlib.Path(file.name).name,  # get the filename from the path
                    file,
                    mimetypes.guess_type(file.name)[0],
                ),
            )
        )

    # Setup multipart form data
    fields = [
        ("utf8", "✓"),
        ("authenticity_token", auth_token),
        ("submission[method]", "upload"),
        *form_files,
    ]
    if leaderboard_name is not None:
        fields.append(("submission[leaderboard_name]", leaderboard_name))

    multipart = MultipartEncoder(fields=fields)

    headers = {
        "Content-Type": multipart.content_type,
        "Referer": GS_COURSE_ENDPOINT,
    }
    response = session.post(GS_UPLOAD_ENDPOINT, data=multipart, headers=headers)

    # Note: Response status code is always 200 even if upload was unsuccessful (e.g. past the due date,
    # missing form fields, etc.). The response from the server either redirects to the submission page (url)
    # if successful, or redirects to the Course homepage if unsuccessful.
    return (
        None
        if response.url == GS_COURSE_ENDPOINT or response.url.endswith("submissions")
        else response.url
    )


# Where the page's props might keep the id Gradescope wants as owner_id
_OWNER_KEYS = ("owner_id", "ownerId", "current_user_id", "currentUserId", "user_id", "userId")


def _find_owner_id(props):
    """First value under one of _OWNER_KEYS, searching nested props."""
    if isinstance(props, dict):
        for key in _OWNER_KEYS:
            if props.get(key) is not None:
                return props[key]
        children = props.values()
    elif isinstance(props, list):
        children = props
    else:
        return None
    for child in children:
        found = _find_owner_id(child)
        if found is not None:
            return found
    return None


def save_online_answers(
    session: requests.Session,
    course_id: str,
    assignment_id: str,
    answers: dict[str, dict[str, str]],
    files: dict[str, dict[str, list[io.IOBase]]] | None = None,
    gradescope_base_url: str = DEFAULT_GRADESCOPE_BASE_URL,
) -> None:
    """Saves answers to an online assignment, like its "Save Answer" button.

    Args:
        answers: {question id: {input number: answer}}. Typed text as is; for a
            multiple choice, the chosen option's text. Inputs of those questions
            that aren't given keep the answer already saved on Gradescope.
        files: {question id: {input number: [open files]}} for file upload inputs.

    Raises:
        ValueError: if the assignment isn't open for answering, or Gradescope refuses.
    """
    ASSIGNMENT_ENDPOINT = f"{gradescope_base_url}/courses/{course_id}/assignments/{assignment_id}"
    NEW_SUBMISSION_PAGE = f"{ASSIGNMENT_ENDPOINT}/submissions/new"

    response = session.get(NEW_SUBMISSION_PAGE)
    soup = BeautifulSoup(response.text, "html.parser")
    view = soup.find("div", attrs={"data-react-class": "OnlineAssignmentSubmitter"})
    if view is None or not view.get("data-react-props"):
        raise ValueError("This assignment isn't open for answering (it may be closed)")
    props = json.loads(view["data-react-props"])

    owner_id = _find_owner_id(props)
    if owner_id is None:
        raise ValueError(
            "Couldn't find your Gradescope user id on the assignment page "
            f"(it has: {', '.join(sorted(props))})"
        )

    # The page sends a whole question's answers at once, so keep what's already
    # saved. Only text and choices: files already uploaded aren't sent again.
    saved = props.get("answers") or {}
    questions = {}
    for qid in {*answers, *(files or {})}:
        before = saved.get(qid) if isinstance(saved.get(qid), dict) else {}
        questions[qid] = {
            **{n: v for n, v in before.items() if isinstance(v, str)},
            **answers.get(qid, {}),
        }

    fields = [
        ("questions", json.dumps(questions)),
        ("owner_id", str(owner_id)),
        ("outline_hash", props["outlineHash"]),
    ]
    for qid, inputs in (files or {}).items():
        for number, handles in inputs.items():
            for f in handles:
                name = pathlib.Path(f.name).name
                fields.append((
                    f"assignment_submission_files[{qid}][{number}][]",
                    (name, f, mimetypes.guess_type(name)[0] or "application/octet-stream"),
                ))
    multipart = MultipartEncoder(fields=fields)
    response = session.post(
        f"{ASSIGNMENT_ENDPOINT}/submissions",
        data=multipart,
        headers={
            "Content-Type": multipart.content_type,
            "X-CSRF-Token": soup.find("meta", {"name": "csrf-token"})["content"],
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "*/*",
            "Referer": NEW_SUBMISSION_PAGE,
        },
    )
    if response.status_code != requests.codes.ok:
        raise ValueError(f"Gradescope didn't save the answers ({response.status_code})")
