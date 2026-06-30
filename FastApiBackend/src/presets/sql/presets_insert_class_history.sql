-- One class_history row for a seeded past occurrence. This gym's history was
-- wiped first (presets_delete_class_history.sql) and the classes are freshly
-- inserted, so each (class_id, occurred_at) is unique within the import — no
-- ON CONFLICT is needed here (unlike the live lazy/reconciler materialize).
INSERT INTO class_history (
    class_id, gym_id, instructor_id, occurred_at, duration_minutes
) VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:instructor_id AS UUID),
    CAST(:occurred_at AS TIMESTAMPTZ),
    :duration_minutes
)
RETURNING class_history_id
