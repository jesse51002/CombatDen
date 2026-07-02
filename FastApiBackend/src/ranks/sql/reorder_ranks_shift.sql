-- Phase 1 of the atomic reorder: shift every listed rank's main order
-- out of the target value space (+100000) so phase 2 can assign final
-- orders without ever transiently colliding on the
-- UNIQUE (gym_id, main_rank_num_order, sub_rank_num_order) constraint
-- (which is non-deferrable, so it is checked per row). Two shifted rows
-- never collide because their original (main, sub) pairs are unique.
UPDATE gym_ranks
SET main_rank_num_order = main_rank_num_order + 100000
WHERE gym_id = CAST(:gym_id AS UUID)
  AND rank_id IN (
      SELECT CAST(elem ->> 'rank_id' AS UUID)
      FROM jsonb_array_elements(CAST(:ranks AS JSONB)) AS elem
  )
