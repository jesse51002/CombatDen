-- Move every member currently on ANY sub-rank of the group onto the
-- replacement rank (or NULL when the group is the gym's only one),
-- so the composite FK on members never dangles when the group's rows
-- are deleted.
UPDATE members m
SET current_rank_id = :new_rank_id
WHERE m.gym_id = :gym_id
  AND m.current_rank_id IN (
      SELECT rank_id
      FROM gym_ranks
      WHERE gym_id = :gym_id
        AND main_rank_num_order = :main_rank_num_order
  )
