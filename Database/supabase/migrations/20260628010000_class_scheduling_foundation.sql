-- Hand-authored migration.
-- Class scheduling foundation: additive, non-destructive changes that reach the
-- schemas/ end state for class_history and class_instance_exceptions.
--   * class_history gains uq_class_history_occurrence UNIQUE (class_id, occurred_at) —
--     the idempotency anchor for the find-or-create (ON CONFLICT) materialize path.
--   * class_instance_exceptions gains a new_date DATE reschedule target plus a
--     future-only CHECK (new_date IS NULL OR new_date > original_date).
-- new_date is intentionally staff-editable, so it is NOT added to any REVOKE UPDATE
-- list; class_history has no UPDATE policy. No view selects from either table, so no
-- view recreation is needed.

-- Guard: the UNIQUE add below fails mid-migration if duplicate (class_id, occurred_at)
-- pairs already exist. Abort early with a clear message so the data can be deduped first.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM class_history
        GROUP BY class_id, occurred_at
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'class_history has duplicate (class_id, occurred_at) rows; dedupe before adding uq_class_history_occurrence';
    END IF;
END $$;

ALTER TABLE class_history
    ADD CONSTRAINT uq_class_history_occurrence UNIQUE (class_id, occurred_at);

ALTER TABLE class_instance_exceptions
    ADD COLUMN new_date DATE;

ALTER TABLE class_instance_exceptions
    ADD CONSTRAINT chk_instance_exception_new_date_future
        CHECK (new_date IS NULL OR new_date > original_date);
