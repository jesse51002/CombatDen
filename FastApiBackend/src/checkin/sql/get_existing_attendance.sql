-- The existing attendance row for one occurrence, keyed by its identity
-- (class_id, original_date) -- the idempotency read the gate + the writer's
-- ON CONFLICT fallback both use.
SELECT log_id, plan_id, item_id
FROM member_attendance
WHERE member_id = :member_id
  AND class_id = :class_id
  AND original_date = :original_date
