-- Update mutable columns on a gym class. The set_clause (named WITHOUT braces
-- on purpose -- load_sql format_maps comments too) is assembled in the
-- service from the explicitly-set fields, with CAST(...) for the recurring_unit
-- enum and the allowed_plan_ids JSONB column (never :p::type). Returns class_id;
-- the service re-reads via classes_get.sql for the joined response.
UPDATE gym_classes
SET {set_clause}
WHERE class_id = :class_id
RETURNING class_id
