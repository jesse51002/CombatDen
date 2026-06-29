UPDATE gym_employees
SET employee_pic_url = :employee_pic_url,
    employee_public_description = :employee_public_description
WHERE employee_id = CAST(:employee_id AS UUID)
