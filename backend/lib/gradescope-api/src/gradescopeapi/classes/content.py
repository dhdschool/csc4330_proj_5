import pydantic
from datetime import datetime
from typing import Literal, Union, Annotated, Any

class AssignmentContent(pydantic.BaseModel):
    id: int
    title: str
    total_points: str
    student_submission: bool
    due_date: datetime | None
    submission_allowed: bool
    
class AssignmentSubmission(pydantic.BaseModel):
    id: int
    created_at: datetime | None
    score: str | None = None
    
class QuestionSubmission(pydantic.BaseModel):
    score: str | None = None
    question_id: int
    data: dict
    active: bool
    answers: dict
    id: int

class TextContent(pydantic.BaseModel):
    type: Literal["text"]
    value: str

class FileUploadInput(pydantic.BaseModel):
    type: Literal["file_upload_input"]

class FreeResponseInput(pydantic.BaseModel):
    type: Literal["free_response_input"]

class RadioChoices(pydantic.BaseModel):
    value: str

class RadioInput(pydantic.BaseModel):
    type: Literal["radio_input"]
    choices: list[RadioChoices]

QuestionContent = Annotated[Union[TextContent, FileUploadInput, FreeResponseInput, RadioInput], pydantic.Field(discriminator="type")]

    
class Question(pydantic.BaseModel):
    id: int
    title: str
    index: int
    weight: str
    scoring_type: str
    content: list[QuestionContent]

class FilesContentDict(pydantic.BaseModel):
    url: pydantic.HttpUrl

class FilesContent(pydantic.BaseModel): 
    id: int
    file: FilesContentDict
    path: str
    file_size: int
    content_type: str
    url: pydantic.HttpUrl

class AssignmentSubmissionContent(pydantic.BaseModel):
    type: Literal["content"] = "content"
    assignment: AssignmentContent
    assignment_submission: AssignmentSubmission | None
    question_submissions: list[QuestionSubmission]
    questions: list[Question]
    text_files: list[FilesContent]

class OutlineContent(pydantic.BaseModel):
    id: int
    type: str
    title: str
    parent_id: int | None
    weight: str
    content: list[QuestionContent]
    index: int

class QuestionSubmissionsView(pydantic.BaseModel):
    id: int
    question_id: int
    assignment_submission_id: int
    created_at: datetime
    updated_at: datetime 
    answers: dict[str, Any]
    question: Question
    
class OnlineAssignmentSubmitterContent(pydantic.BaseModel):
    type: Literal["new_submission"] = "new_submission"
    title: str
    outline: list[OutlineContent]
    outlineHash: str
    answers: dict[str, dict[str, Any]]
    questionSubmissions: dict[str, QuestionSubmissionsView]
    files: list[FilesContent]
    
SubmissionContent = Union[OnlineAssignmentSubmitterContent | AssignmentSubmissionContent]    

class Content(pydantic.BaseModel):
    content: SubmissionContent