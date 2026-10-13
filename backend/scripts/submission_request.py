if __name__ == "__main__":
    import os
    import dotenv
    from gradescopeapi.classes.connection import GSConnection
    from gradescopeapi.classes.account import Account
    from gradescopeapi.classes.assignments import Assignment
    dotenv.load_dotenv()
    
    connection = GSConnection()
    connection.login(os.getenv('EMAIL'), os.getenv('PASSWORD'))
    assert connection.account != None
    
    def reconstruct_submission_url(course_id: str, assignment: Assignment): 
        return f"{connection.gradescope_base_url}/courses/{course_id}/assignments/{assignment.assignment_id}/submissions/{assignment.submission_id}"
    
    account: Account = connection.account
    
    courses = account.get_courses()
    course_iter = iter(courses["student"])
    first_course_id = next(course_iter)
    assignments = account.get_assignments(first_course_id)
    
    first_assignment = assignments[0]

    assert first_assignment.assignment_id != None
    assert first_assignment.submission_id != None
    
    print(reconstruct_submission_url(first_course_id, first_assignment))
    
    connection.logout()