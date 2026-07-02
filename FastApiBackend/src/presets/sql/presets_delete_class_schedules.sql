-- Idempotency (demo reset): wipe this gym's schedule versions before its
-- classes are hard-deleted (gym_class_schedules FKs gym_classes).
DELETE FROM gym_class_schedules WHERE gym_id = CAST(:gym_id AS UUID)
