-- Instance exceptions for one class whose original_date falls in the
-- window. Mirrors src/classes/sql/classes_instance_exception_list.sql --
-- checkin owns its own copy per the per-domain SQL ownership convention.
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
WHERE class_id = :class_id
  AND original_date >= :start_date
  AND original_date <= :end_date
ORDER BY original_date ASC
