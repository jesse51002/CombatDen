UPDATE members
SET current_rank_id = (
    SELECT rank_id
    FROM gym_ranks
    WHERE gym_id = :gym_id
    ORDER BY main_rank_num_order ASC, sub_rank_num_order ASC
    LIMIT 1
)
WHERE gym_id = :gym_id
  AND current_rank_id IS NULL
  AND EXISTS (
      SELECT 1 FROM gym_ranks WHERE gym_id = :gym_id
  )
