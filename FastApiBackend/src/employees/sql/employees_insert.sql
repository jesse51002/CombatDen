INSERT INTO gym_employees (
    gym_id,
    employee_type,
    first_name,
    last_name,
    phone,
    email,
    employee_public_description
) VALUES (
    CAST(:gym_id AS UUID),
    CAST(:employee_type AS employee_type),
    :first_name,
    :last_name,
    :phone,
    :email,
    :employee_public_description
)
RETURNING employee_id
