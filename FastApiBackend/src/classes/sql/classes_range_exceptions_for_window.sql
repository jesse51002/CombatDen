-- Every range exception of a gym that overlaps the window.
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
WHERE gym_id = :gym_id
  AND start_date <= :end_date
  AND end_date >= :start_date
