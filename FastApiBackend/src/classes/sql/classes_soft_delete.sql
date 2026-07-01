-- Soft-delete a gym class: mark deleted and deactivate it. Runs AFTER the
-- future-keyed wipe in the same transaction (the service order matters: the
-- wipe's points load reads the still-live class row). Past occurrences keep
-- rendering forever from the class's immutable schedule versions.
UPDATE gym_classes
SET is_deleted = TRUE,
    is_active = FALSE
WHERE class_id = :class_id
RETURNING class_id
