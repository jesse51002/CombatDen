-- Resolve the existing class_history row for a (class, occurrence instant)
-- after a losing ON CONFLICT DO NOTHING materialize. Keyed on the same
-- (class_id, occurred_at) pair the uq_class_history_occurrence constraint pins.
SELECT class_history_id
FROM class_history
WHERE class_id = CAST(:class_id AS UUID)
  AND occurred_at = CAST(:occurred_at AS TIMESTAMPTZ)
