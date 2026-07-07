SELECT
    gym_id,
    is_rank_enabled
FROM gyms
WHERE gym_id = CAST(:gym_id AS UUID)
