UPDATE members
SET current_rank_id = CAST(:new_rank_id AS UUID)
WHERE member_id = CAST(:member_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
RETURNING member_id, current_rank_id
