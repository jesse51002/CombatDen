-- Remove one member's attendance from an occurrence, keyed by its identity
-- (class_id, original_date), returning the billing attribution (item_id /
-- plan_id, both NULL for a no-membership row) so the caller can reverse an
-- auto-end on the charged pack. Returns no row when the member was not
-- checked in to this occurrence.
DELETE FROM member_attendance
WHERE member_id = CAST(:member_id AS UUID)
  AND class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
RETURNING item_id, plan_id
