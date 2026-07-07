UPDATE gyms
SET is_rank_enabled = :is_rank_enabled
WHERE gym_id = CAST(:gym_id AS UUID)
RETURNING
    gym_id,
    is_rank_enabled
