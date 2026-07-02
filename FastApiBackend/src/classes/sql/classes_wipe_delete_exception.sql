-- Delete one instance exception whose original slot no longer exists under a
-- newly-minted schedule version (the uniform version-change wipe). Keyed by
-- the exact slot -- a same-day sibling slot's exception is untouched.
DELETE FROM class_instance_exceptions
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
  AND original_time = CAST(:original_time AS TIME)
