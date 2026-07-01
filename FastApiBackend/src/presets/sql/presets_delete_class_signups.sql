-- Idempotency (demo reset): wipe this gym's sign-up reservations before its
-- classes are hard-deleted (class_signups FKs gym_classes), so a re-import
-- mints a clean set of reservations instead of leaving orphans behind.
DELETE FROM class_signups WHERE gym_id = CAST(:gym_id AS UUID)
