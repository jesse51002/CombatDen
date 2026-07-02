-- Display names for a set of instructors (weekday_slots instructor_ids),
-- resolved in ONE lookup and merged into the response slots in Python --
-- replaces the old seven per-weekday LEFT JOINs.
SELECT
    employee_id,
    (first_name || ' ' || last_name) AS instructor_name
FROM gym_employees
WHERE employee_id = ANY(CAST(:employee_ids AS UUID[]))
