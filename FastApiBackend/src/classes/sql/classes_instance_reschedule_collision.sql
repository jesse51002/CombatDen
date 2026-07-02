-- Other (different original SLOT) non-cancelled reschedules already targeting
-- the same new_date for this class -> candidate double-books the 1-day
-- expansion can't see (it only visits the target date itself, keyed on the
-- original slot). The moved slot excludes ITSELF by the full
-- (original_date, original_time) pair — a same-day sibling slot is a genuine
-- candidate. Returns the candidates with their times; the service resolves
-- each one's EFFECTIVE time in Python (new_class_time when set, else its own
-- original_time — the slot the exception is bound to) and rejects only an
-- exact time match. Landing on a busy day at a DIFFERENT time is allowed.
SELECT
    exception_id,
    original_date,
    original_time,
    new_date,
    new_class_time
FROM class_instance_exceptions
WHERE class_id = :class_id
  AND new_date = :new_date
  AND (original_date, original_time)
      <> (CAST(:original_date AS DATE), CAST(:original_time AS TIME))
  AND is_cancelled = FALSE
