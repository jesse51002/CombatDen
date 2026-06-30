-- Idempotency (demo reset): wipe this gym's class_history after its attendance
-- (FK order) so a re-import regenerates a clean past month of occurrences.
DELETE FROM class_history WHERE gym_id = CAST(:gym_id AS UUID)
