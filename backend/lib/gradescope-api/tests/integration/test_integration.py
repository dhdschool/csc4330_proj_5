from datetime import datetime, timedelta


from gradescopeapi.classes.extensions import update_student_extension
from gradescopeapi.classes.account import Account
from gradescopeapi.classes.connection import GSConnection


def test_add_or_edit_student_extension(create_connection):
    course_id = "753413"
    assignment_id = "4330410"
    release_date = datetime(2024, 4, 15)
    due_date = release_date + timedelta(days=1)
    late_due_date = due_date + timedelta(days=1)

    # fetch instructor connection
    connection: GSConnection = create_connection("instructor")
    assert isinstance(connection, GSConnection)

    # get course members
    assert isinstance(connection.account, Account)
    members = connection.account.get_course_users(course_id)

    # assert at least 1 student account exists in course
    assert members is not None and len(members) > 0
    student_members = [member for member in members if member.role.lower() == "student"]
    assert len(student_members) > 0

    for student in student_members:
        assert student.user_id is not None  # students should have a user_id

        # try updating the extension for this user
        result = update_student_extension(
            connection.session,
            course_id,
            assignment_id,
            student.user_id,
            release_date,
            due_date,
            late_due_date,
        )
        assert result, "Failed to update student extension"
