-- Move every member on the deleted rank onto the replacement rank (or
-- NULL when it was the gym's only rank), pinning them to the
-- replacement's BASE leaf: sub-index 0 when it has sub-ranks, else NULL
-- (keeping the count==0 <=> sub_index NULL invariant). Silent — a
-- deletion is not a promotion, so no rank_changed activity is written.
UPDATE members
SET current_rank_id = CAST(:new_rank_id AS UUID),
    current_sub_index = CASE
        WHEN (
            SELECT sub_rank_count
            FROM gym_ranks
            WHERE rank_id = CAST(:new_rank_id AS UUID)
        ) > 0 THEN 0
        ELSE NULL
    END
WHERE current_rank_id = CAST(:old_rank_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
