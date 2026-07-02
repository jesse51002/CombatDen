-- Remove one member's sign-up for an occurrence. Returns the deleted
-- signup_id, or no row when the member had no sign-up for this occurrence.
-- Keyed by the full slot (original_date AND original_time) -- a class may
-- occur several times per day.
DELETE FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
  AND original_time = CAST(:original_time AS TIME)
RETURNING signup_id
