-- Rename a whole main-rank group in one atomic UPDATE. main_name is
-- denormalized onto every sub-rank row, so the group rename touches
-- every row sharing the (gym_id, main_rank_num_order) pair.
UPDATE gym_ranks
SET main_name = :new_main_name
WHERE gym_id = :gym_id
  AND main_rank_num_order = :main_rank_num_order
RETURNING rank_id
