-- Delete every sign-up for one occurrence (identity key: class_id +
-- original_date). Used by cancel-occurrence (a cancelled occurrence can't be
-- attended, so its reservations are dead rows) and by the mint engine's wipe
-- for an occurrence whose original slot no longer exists.
DELETE FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
