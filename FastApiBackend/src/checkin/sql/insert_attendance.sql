-- Record one member's attendance at a materialized occurrence. plan_id/item_id
-- are the billing attribution; they are passed together as NULL for a staff
-- check-in of a member with no covering membership (no pack is drawn). The
-- chk_attendance_membership_pair CHECK keeps the pair both-set or both-NULL.
INSERT INTO member_attendance (member_id, gym_id, class_history_id, plan_id, item_id)
VALUES (:member_id, :gym_id, :class_history_id, :plan_id, :item_id)
ON CONFLICT (member_id, class_history_id) DO NOTHING
RETURNING log_id
