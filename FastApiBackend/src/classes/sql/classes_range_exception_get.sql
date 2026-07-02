-- One range exception, scoped to its class. class_id alone would already
-- disambiguate the gym (FK'd to one gym_classes row); the filter is
-- defense-in-depth against a caller passing a mismatched class_id in the URL.
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
WHERE exception_id = :exception_id
  AND class_id = :class_id
