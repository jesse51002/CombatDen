-- Delete one range exception, scoped to its class. Covered dates simply
-- revive on the next expansion -- anything already torn down while the
-- range was active is not restored (see the exceptions service docstring).
DELETE FROM class_range_exceptions
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
