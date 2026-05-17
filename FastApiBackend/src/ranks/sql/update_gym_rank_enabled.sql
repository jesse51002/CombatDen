UPDATE gyms
SET is_rank_enabled = :is_rank_enabled
WHERE gym_id = :gym_id
RETURNING
    gym_id,
    is_rank_enabled
