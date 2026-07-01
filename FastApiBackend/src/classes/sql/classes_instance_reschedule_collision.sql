-- Another (different original_date) non-cancelled reschedule already targeting
-- the SAME target instant (new_date + effective start time) for this class -> a
-- double-book the 1-day expander can't see (it only visits the target date
-- itself, keyed on original_date). Time-aware: a colliding reschedule's
-- effective time is its own new_class_time when set, else the class default
-- (:class_time); it collides only when that equals the moved occurrence's
-- effective time (:effective_time). Landing on a busy day at a DIFFERENT time is
-- allowed. Returns the colliding rows, if any.
SELECT
    exception_id,
    original_date,
    new_date
FROM class_instance_exceptions
WHERE class_id = :class_id
  AND new_date = :new_date
  AND original_date <> :original_date
  AND is_cancelled = FALSE
  AND COALESCE(new_class_time, CAST(:class_time AS TIME))
      = CAST(:effective_time AS TIME)
