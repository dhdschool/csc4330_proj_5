from dataclasses import dataclass
from enum import Enum
import pathlib

class FileType(Enum):
    VIDEO = 1
    IMAGE = 2
    BLOB = 3

@dataclass
class Content:
    content_id: str
    question_id: str
    index: int

@dataclass
class FormContent(Content):
    text: str

@dataclass
class RadioContent(Content):
    options: list[str]
    selected: int | None # Index of selected item

    def get_selected(self) -> str | None:
        """Returns the selected option if present"""
        if self.selected is None or self.selected < 0 or self.selected > len(self.options):
            return None
        else:
            return self.options[self.selected]
    
@dataclass
class FileContent(Content): 
    is_populated: bool
    file_type: FileType
    binary: bytes | None
    name: str | None
    
    def get_extension(self) -> str | None:
        """Returns .txt from dir1/dir2/example.txt from a given file"""
        if self.name is None:
            return None
        else: 
            return pathlib.Path(self.name).suffix
    
@dataclass
class TextContent(Content):
    text: str


@dataclass
class Question:
    question_id: str
    points: int
    title: str
    content: list[Content]
