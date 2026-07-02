-- The mint engine's wipe collection: a class's sign-ups on/after the mint's
-- gym-local floor date. The instant test (original slot >= the mint instant,
-- computed per row from original_date + original_time in the outgoing
-- version's timezone) happens in Python — rows store the wall-clock key.
SELECT
    signup_id,
    member_id,
    original_date,
    original_time
FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:floor_date AS DATE)
