-- Resolve the class a class_history occurrence belongs to (for the
-- eligibility gate). Returns no row when the instance does not exist.
SELECT class_id
FROM class_history
WHERE class_history_id = :class_history_id
  AND gym_id = :gym_id
