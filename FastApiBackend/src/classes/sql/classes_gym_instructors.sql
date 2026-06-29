-- The gym's employees, for resolving an effective instructor_id to a display
-- name when building the schedule board.
SELECT
    employee_id,
    first_name,
    last_name
FROM gym_employees
WHERE gym_id = :gym_id
