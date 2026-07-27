-- The gym's employees, for resolving an effective instructor_id to a display
-- name, public bio, and photo when building the schedule board.
SELECT
    employee_id,
    first_name,
    last_name,
    employee_public_description,
    employee_pic_url
FROM gym_employees
WHERE gym_id = :gym_id
