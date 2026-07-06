-- Phase 1 of the atomic reorder: shift every listed rank's main order
-- out of the target value space (+100000) so phase 2 can assign final
-- orders without ever transiently colliding on the
-- UNIQUE (gym_id, main_rank_num_order) constraint (which is
-- non-deferrable, so it is checked per row). Two shifted rows never
-- collide because their original main orders are unique.
--
-- The +100000 offset MUST stay in sync with REORDER_SHIFT_OFFSET in
-- src/ranks/service/ranks_groups.py — the reorder guard rejects any
-- payload target main order >= that constant so this shift can never
-- collide with a valid target. Change one, change the other.
UPDATE gym_ranks
SET main_rank_num_order = main_rank_num_order + 100000
WHERE gym_id = CAST(:gym_id AS UUID)
  AND rank_id IN (
      SELECT CAST(elem ->> 'rank_id' AS UUID)
      FROM jsonb_array_elements(CAST(:ranks AS JSONB)) AS elem
  )
