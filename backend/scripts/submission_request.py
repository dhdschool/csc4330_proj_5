if __name__ == "__main__":
    import os
    import dotenv
    from gradescopeapi.classes.connection import GSConnection
    from gradescopeapi.classes.account import Account
    from gradescopeapi.classes.assignments import Assignment
    from bs4 import BeautifulSoup
    from gradescopeapi.classes.content import Content
    import json
    dotenv.load_dotenv()
    
    connection = GSConnection()
    connection.login(os.getenv('EMAIL'), os.getenv('PASSWORD'))
    assert connection.account != None
    
    def reconstruct_submission_url(course_id: str, assignment: Assignment): 
        return f"{connection.gradescope_base_url}/courses/{course_id}/assignments/{assignment.assignment_id}/submissions/{assignment.submission_id}"
    
    def get_submission(course_id: str, assignment: Assignment) -> BeautifulSoup:
        url = f"{connection.gradescope_base_url}/courses/{course_id}/assignments/{assignment.assignment_id}"
        html = connection.session.get(url).text
        return BeautifulSoup(html, "html.parser")
        
    
    
    account: Account = connection.account
    
    courses = account.get_courses()
    course_iter = iter(courses["student"])
    first_course_id = next(course_iter)
    assignments = account.get_assignments(first_course_id)
    
    first_assignment = assignments[-1]

    assert first_assignment.assignment_id != None
    
    content = account.get_assignment_content(first_course_id, first_assignment.assignment_id)
    print(content.model_dump_json(indent=1))
    