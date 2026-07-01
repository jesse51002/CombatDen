-- Remove one member's sign-up for an occurrence. Returns the deleted
-- signup_id, or no row when the member had no sign-up for this occurrence.
DELETE FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND occurrence_date = CAST(:occurrence_date AS DATE)
RETURNING signup_id
