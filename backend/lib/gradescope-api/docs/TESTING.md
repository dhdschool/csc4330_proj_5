# Testing

Tests are performed using real Gradescope accounts to interact with the Gradescope server. As such, valid Gradescope accounts and courses are required to run the tests.

## Outside Contributors

Unfortunately, the tests right now are not structured for use by outside contributors. This is because they rely on test accounts and specific course setups in Gradescope and are not shared publicly. In the future we may look into how to improve the testing experience for outside contributors.

For now, the best way to test your changes is to create a test script and run it.

For example:

```python
# example.py

from gradescopeapi.classes.connection import GSConnection

# create connection and login
connection = GSConnection()
connection.login("email@domain.com", "password")

"""
Fetching all courses for user
"""
courses = connection.account.get_courses()
for course in courses["instructor"]:
    print(course)
for course in courses["student"]:
    print(course)
```

```bash
uv run example.py
```

## Environment

Create an `.env` file in the root directory of the project with the following environment variables:

```
GRADESCOPE_CI_STUDENT_EMAIL
GRADESCOPE_CI_STUDENT_PASSWORD
GRADESCOPE_CI_INSTRUCTOR_EMAIL
GRADESCOPE_CI_INSTRUCTOR_PASSWORD
GRADESCOPE_CI_TA_EMAIL
GRADESCOPE_CI_TA_PASSWORD
```

For test cases to pass:

Student accounts are expected to be accounts that are **only** enrolled as students in courses. Similarly, instructor accounts are expected to **only** be instructors for courses. TA/Reader accounts are expected to be **both**. Tests can also be skipped by using the pytest decorator `@pytest.mark.skip(reason="...")`

## Running Tests Locally

Tests can be run locally using `pytest`.

```bash
just test
just test-cov
```

## Running Tests on CI

Tests are run automatically using GitHub Actions.

## Running CI Locally

Install [act](https://github.com/nektos/act)

From the root of the repository, run the following command and pass in the `.env` file for Gradescope test account credentials:

```bash
act --secret-file .env
```
