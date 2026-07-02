-- Delete every sign-up for one occurrence (identity key: class_id +
-- original_date + original_time -- the exact slot; a same-day sibling
-- occurrence's reservations are untouched). Used by cancel-occurrence (a
-- cancelled occurrence can't be attended, so its reservations are dead rows)
-- and by the mint engine's wipe for a slot the new shape no longer produces.
DELETE FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
  AND original_time = CAST(:original_time AS TIME)
