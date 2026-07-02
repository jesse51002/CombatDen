-- Every instance exception of a gym whose original_date falls in the window
-- OR whose reschedule target (new_date) does. The second leg is what makes a
-- cross-window reschedule visible: an occurrence moved INTO the window keeps
-- its out-of-window original_date (the identity the expander enumerates by),
-- so the board widens its expansion bounds around these rows — without them
-- the moved session would be invisible in exactly the week it moved into.
SELECT
    exception_id,
    class_id,
    gym_id,
    original_date,
    original_time,
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_max_capacity,
    new_instructor_id,
    new_date,
    created_at
FROM class_instance_exceptions
WHERE gym_id = :gym_id
  AND (
    (original_date >= :start_date AND original_date <= :end_date)
    OR (new_date >= :start_date AND new_date <= :end_date)
  )
