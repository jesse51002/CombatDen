-- Find-or-create the class_history row for one class occurrence. The
-- uq_class_history_occurrence UNIQUE (class_id, occurred_at) constraint is the
-- idempotency anchor: ON CONFLICT DO NOTHING makes a concurrent materialize a
-- no-op (RETURNING is then empty, and the caller SELECTs the winner's row via
-- classes_history_find.sql).
INSERT INTO class_history (class_id, gym_id, occurred_at, instructor_id, duration_minutes)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:occurred_at AS TIMESTAMPTZ),
    CAST(:instructor_id AS UUID),
    :duration_minutes
)
ON CONFLICT ON CONSTRAINT uq_class_history_occurrence DO NOTHING
RETURNING class_history_id
