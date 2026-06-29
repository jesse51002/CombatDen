-- Every instance exception of a gym whose original_date falls in the window.
-- These are the exceptions the expander consults for candidate dates in
-- [start_date, end_date] (it indexes by original_date).
SELECT
    exception_id,
    class_id,
    gym_id,
    original_date,
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_max_capacity,
    new_instructor_id,
    new_date,
    created_at
FROM class_instance_exceptions
WHERE gym_id = :gym_id
  AND original_date >= :start_date
  AND original_date <= :end_date
