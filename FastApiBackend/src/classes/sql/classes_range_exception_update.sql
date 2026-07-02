-- Move a range exception's dates. is_cancelled / new_instructor_id are fixed
-- at creation and are not touched here.
UPDATE class_range_exceptions
SET start_date = :start_date,
    end_date = :end_date
WHERE exception_id = :exception_id
  AND class_id = :class_id
RETURNING
    exception_id,
    class_id,
    gym_id,
    start_date,
    end_date,
    is_cancelled,
    new_instructor_id,
    created_at
