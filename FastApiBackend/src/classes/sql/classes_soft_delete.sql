-- Soft-delete a gym class: mark deleted and deactivate it (history rows are
-- decoupled, so this never touches class_history / attendance).
UPDATE gym_classes
SET is_deleted = TRUE,
    is_active = FALSE
WHERE class_id = :class_id
RETURNING class_id
