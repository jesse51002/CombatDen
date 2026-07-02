-- Idempotency (demo reset): wipe this gym's single-date overrides before its
-- classes are hard-deleted (class_instance_exceptions FKs gym_classes). The
-- import never writes instance exceptions today, but the delete runs
-- unconditionally so a re-import stays correct if that ever changes.
DELETE FROM class_instance_exceptions WHERE gym_id = CAST(:gym_id AS UUID)
