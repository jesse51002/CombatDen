-- Idempotency (demo reset): wipe this gym's attendance before re-materializing
-- the past month, so a re-import doesn't pile up duplicate history. Runs BEFORE
-- presets_delete_class_history.sql (member_attendance FKs class_history).
DELETE FROM member_attendance WHERE gym_id = CAST(:gym_id AS UUID)
