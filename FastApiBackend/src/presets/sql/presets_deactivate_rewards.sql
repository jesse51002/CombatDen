UPDATE gym_rewards
SET is_active = FALSE
WHERE gym_id = CAST(:gym_id AS UUID) AND is_active = TRUE
