DELETE FROM gym_ranks
WHERE gym_id = :gym_id
  AND main_rank_num_order = :main_rank_num_order
