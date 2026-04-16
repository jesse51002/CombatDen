-- Bootstrap the gym owner employee row.
-- Runs under the service role so the RLS insert policy does not
-- apply; the row references gyms_unfiltered(gym_id) directly.
INSERT INTO gym_employees (
    user_id,
    gym_id,
    employee_type,
    first_name,
    last_name,
    email
)
VALUES (
    :user_id,
    :gym_id,
    'owner',
    :first_name,
    :last_name,
    :email
)
RETURNING *;
