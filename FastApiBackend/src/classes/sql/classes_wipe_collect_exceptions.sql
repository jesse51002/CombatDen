-- The mint engine's wipe collection: a class's instance exceptions on/after
-- the mint's gym-local floor date. An exception's slot time is the OUTGOING
-- version's class_time on its original_date (exceptions don't store a time
-- key); the instant test happens in Python. Non-surviving exceptions are
-- DELETEd — a dangling exception would zombie-apply if a later version
-- reintroduced its date.
SELECT
    exception_id,
    original_date
FROM class_instance_exceptions
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:floor_date AS DATE)
