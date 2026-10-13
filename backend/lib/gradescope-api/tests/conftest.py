import os

import pytest
from dotenv import load_dotenv

from gradescopeapi.classes.connection import GSConnection
from gradescopeapi.classes.account import Account
import requests
from typing import Callable

load_dotenv()

GRADESCOPE_CI_STUDENT_EMAIL = os.getenv("GRADESCOPE_CI_STUDENT_EMAIL")
GRADESCOPE_CI_STUDENT_PASSWORD = os.getenv("GRADESCOPE_CI_STUDENT_PASSWORD")
GRADESCOPE_CI_TA_EMAIL = os.getenv("GRADESCOPE_CI_TA_EMAIL")
GRADESCOPE_CI_TA_PASSWORD = os.getenv("GRADESCOPE_CI_TA_PASSWORD")
GRADESCOPE_CI_INSTRUCTOR_EMAIL = os.getenv("GRADESCOPE_CI_INSTRUCTOR_EMAIL")
GRADESCOPE_CI_INSTRUCTOR_PASSWORD = os.getenv("GRADESCOPE_CI_INSTRUCTOR_PASSWORD")


@pytest.fixture
def create_session():
    def _create_session(account_type: str = "student") -> requests.Session:
        """Creates and returns a session for testing"""
        connection = GSConnection()

        match account_type.lower():
            case "student":
                connection.login(
                    GRADESCOPE_CI_STUDENT_EMAIL, GRADESCOPE_CI_STUDENT_PASSWORD
                )
            case "ta":
                connection.login(GRADESCOPE_CI_TA_EMAIL, GRADESCOPE_CI_TA_PASSWORD)
            case "instructor":
                connection.login(
                    GRADESCOPE_CI_INSTRUCTOR_EMAIL, GRADESCOPE_CI_INSTRUCTOR_PASSWORD
                )
            case _:
                raise ValueError(
                    "Invalid account type: must be 'student', 'ta', or 'instructor'"
                )

        return connection.session

    return _create_session


@pytest.fixture
def create_account():
    def _create_account(account_type: str = "student") -> Account:
        """Creates and returns an Account for testing"""
        connection = GSConnection()

        match account_type.lower():
            case "student":
                connection.login(
                    GRADESCOPE_CI_STUDENT_EMAIL, GRADESCOPE_CI_STUDENT_PASSWORD
                )
            case "ta":
                connection.login(GRADESCOPE_CI_TA_EMAIL, GRADESCOPE_CI_TA_PASSWORD)
            case "instructor":
                connection.login(
                    GRADESCOPE_CI_INSTRUCTOR_EMAIL, GRADESCOPE_CI_INSTRUCTOR_PASSWORD
                )
            case _:
                raise ValueError(
                    "Invalid account type: must be 'student', 'ta', or 'instructor'"
                )

        return connection.account

    return _create_account


@pytest.fixture
def create_connection() -> Callable[[str], GSConnection]:
    def _create_connection(account_type: str = "student") -> GSConnection:
        """Creates and returns an connection for testing"""
        connection = GSConnection()

        match account_type.lower():
            case "student":
                connection.login(
                    GRADESCOPE_CI_STUDENT_EMAIL, GRADESCOPE_CI_STUDENT_PASSWORD
                )
            case "ta":
                connection.login(GRADESCOPE_CI_TA_EMAIL, GRADESCOPE_CI_TA_PASSWORD)
            case "instructor":
                connection.login(
                    GRADESCOPE_CI_INSTRUCTOR_EMAIL, GRADESCOPE_CI_INSTRUCTOR_PASSWORD
                )
            case _:
                raise ValueError(
                    "Invalid account type: must be 'student', 'ta', or 'instructor'"
                )

        return connection

    return _create_connection
