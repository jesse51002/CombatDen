UPDATE gym_classes
SET is_deleted = TRUE, is_active = FALSE
WHERE gym_id = CAST(:gym_id AS UUID) AND is_deleted = FALSE
