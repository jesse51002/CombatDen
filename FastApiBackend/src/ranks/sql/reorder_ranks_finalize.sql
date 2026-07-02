-- Phase 2 of the atomic reorder: assign each listed rank its final
-- (main, sub) order from the payload. Because phase 1 moved every listed
-- row's main order into the +100000 space, no final target (all < 100000)
-- can collide with another row's pre-update value, so the per-row unique
-- check passes regardless of update order. Targets are mutually unique
-- (a valid permutation), so the end state is consistent.
UPDATE gym_ranks AS g
SET main_rank_num_order = CAST(elem ->> 'main_rank_num_order' AS INTEGER),
    sub_rank_num_order = CAST(elem ->> 'sub_rank_num_order' AS INTEGER)
FROM jsonb_array_elements(CAST(:ranks AS JSONB)) AS elem
WHERE g.rank_id = CAST(elem ->> 'rank_id' AS UUID)
  AND g.gym_id = CAST(:gym_id AS UUID)
