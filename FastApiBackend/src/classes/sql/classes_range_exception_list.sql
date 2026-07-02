-- Range exceptions for one class that overlap the window.
SELECT
    exception_id,
    class_id,
    gym_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id,
    created_at
FROM class_range_exceptions
WHERE class_id = :class_id
  AND start_date <= :end_date
  AND end_date >= :start_date
ORDER BY start_date ASC, created_at ASC
