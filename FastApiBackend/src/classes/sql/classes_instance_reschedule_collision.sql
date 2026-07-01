-- Other (different original_date) non-cancelled reschedules already targeting
-- the same new_date for this class -> candidate double-books the 1-day
-- expansion can't see (it only visits the target date itself, keyed on
-- original_date). Returns the candidates with their override time; the
-- service resolves each one's EFFECTIVE time in Python (new_class_time when
-- set, else its own OWNING version's class_time — versions can differ per
-- original date) and rejects only an exact time match. Landing on a busy day
-- at a DIFFERENT time is allowed.
SELECT
    exception_id,
    original_date,
    new_date,
    new_class_time
FROM class_instance_exceptions
WHERE class_id = :class_id
  AND new_date = :new_date
  AND original_date <> :original_date
  AND is_cancelled = FALSE
