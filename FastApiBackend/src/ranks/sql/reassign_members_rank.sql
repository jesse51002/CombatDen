UPDATE members
SET current_rank_id = :new_rank_id
WHERE current_rank_id = :old_rank_id
  AND gym_id = :gym_id
