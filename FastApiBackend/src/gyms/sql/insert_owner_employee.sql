INSERT INTO gym_employees (
    gym_id,
    employee_type,
    first_name,
    last_name,
    phone,
    email
)
VALUES (
    :gym_id,
    'owner',
    :first_name,
    :last_name,
    :phone,
    :email
)
RETURNING
    employee_id,
    gym_id,
    employee_type,
    first_name,
    last_name,
    phone,
    email,
    employee_pic_url,
    employee_public_description,
    created_at
