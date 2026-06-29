-- Another (different original_date) non-cancelled reschedule already targeting
-- the same new_date for this class -> a double-book the 1-day expander can't see
-- (it only visits the target date itself). Returns the colliding rows, if any.
SELECT
    exception_id,
    original_date,
    new_date
FROM class_instance_exceptions
WHERE class_id = :class_id
  AND new_date = :new_date
  AND original_date <> :original_date
  AND is_cancelled = FALSE
