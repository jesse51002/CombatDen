-- The mint engine's wipe collection: a class's instance exceptions on/after
-- the mint's gym-local floor date, with the fields the per-slot wipe decision
-- needs: original_time (the exact slot the exception is bound to),
-- is_cancelled (a cancellation is slot-keyed intent — never wiped, or the
-- cancelled occurrence would silently revive under the new schedule) and
-- new_date / new_class_time (the EFFECTIVE slot — a reschedule whose target
-- already ran anchors real attendance and must survive). The instant tests
-- happen in Python.
SELECT
    exception_id,
    original_date,
    original_time,
    is_cancelled,
    new_date,
    new_class_time
FROM class_instance_exceptions
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:floor_date AS DATE)
