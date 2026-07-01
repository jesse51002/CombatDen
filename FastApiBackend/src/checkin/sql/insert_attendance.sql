-- Record one member's attendance at a class occurrence, keyed by its
-- identity (class_id, original_date). original_time is the owning schedule
-- version's pre-exception slot time; occurred_at is the denormalized
-- EFFECTIVE start instant (exceptions applied), consumed only by
-- time-window SQL (streak / cycle counts / last_class). plan_id/item_id are
-- the billing attribution; passed together as NULL for a staff check-in of
-- a member with no covering membership (no pack is drawn). The
-- chk_attendance_membership_pair CHECK keeps the pair both-set or both-NULL.
INSERT INTO member_attendance (
    member_id, gym_id, class_id, original_date, original_time, occurred_at, plan_id, item_id
)
VALUES (
    :member_id, :gym_id, :class_id, :original_date, :original_time, :occurred_at, :plan_id, :item_id
)
ON CONFLICT (member_id, class_id, original_date) DO NOTHING
RETURNING log_id
