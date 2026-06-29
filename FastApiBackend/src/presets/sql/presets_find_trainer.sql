SELECT employee_id
FROM gym_employees
WHERE gym_id = CAST(:gym_id AS UUID)
    AND employee_type = 'trainer'
    AND first_name = :first_name
    AND last_name = :last_name
LIMIT 1
