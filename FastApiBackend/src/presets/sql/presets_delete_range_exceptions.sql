-- Idempotency (demo reset): wipe this gym's date-range overrides before its
-- classes are hard-deleted (class_range_exceptions FKs gym_classes). The
-- import never writes range exceptions today, but the delete runs
-- unconditionally so a re-import stays correct if that ever changes.
DELETE FROM class_range_exceptions WHERE gym_id = CAST(:gym_id AS UUID)
