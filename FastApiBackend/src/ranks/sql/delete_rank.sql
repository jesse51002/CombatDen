DELETE FROM gym_ranks
WHERE rank_id = CAST(:rank_id AS UUID)
