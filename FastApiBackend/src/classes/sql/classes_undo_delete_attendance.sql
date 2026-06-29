-- Remove every attendance row recorded against one materialized occurrence.
-- Append-only RLS denies authenticated DELETE; this runs at service_role.
-- RETURNING log_id lets the caller count exactly how many rows were removed.
DELETE FROM member_attendance
WHERE class_history_id = CAST(:class_history_id AS UUID)
RETURNING log_id
