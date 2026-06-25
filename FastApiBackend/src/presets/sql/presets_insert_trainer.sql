INSERT INTO gym_employees (
    gym_id, employee_type, first_name, last_name,
    employee_pic_url, employee_public_description
) VALUES (
    CAST(:gym_id AS UUID), 'trainer', :first_name, :last_name,
    :employee_pic_url, :employee_public_description
)
RETURNING employee_id
