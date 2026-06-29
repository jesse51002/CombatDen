-- Current recorded attendance for one materialized class occurrence. Used by
-- the room-capacity gate (count >= max_capacity rejects a non-override
-- check-in).
SELECT COUNT(*) AS attendance_count
FROM member_attendance
WHERE class_history_id = CAST(:class_history_id AS UUID)
