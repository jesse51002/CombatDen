-- Idempotency (demo reset): wipe this gym's attendance before its classes are
-- hard-deleted (member_attendance FKs gym_classes), so a re-import doesn't
-- pile up duplicate/orphaned attendance and regenerates a clean past month.
DELETE FROM member_attendance WHERE gym_id = CAST(:gym_id AS UUID)
