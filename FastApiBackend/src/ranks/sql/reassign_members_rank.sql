-- Move every member on the deleted rank onto the replacement rank (or
-- NULL when it was the gym's only rank), pinning them to the
-- replacement's BASE leaf: sub-index 0 when it has sub-ranks, else NULL
-- (keeping the count==0 <=> sub_index NULL invariant). The EFFECTIVE
-- sub-rank count is 0 whenever the gym's sub_rank_type is 'none' (sub-ranks
-- disabled gym-wide), so a 'none' gym always pins NULL. Silent — a
-- deletion is not a promotion, so no rank_changed activity is written.
UPDATE members
SET current_rank_id = CAST(:new_rank_id AS UUID),
    current_sub_index = CASE
        WHEN (
            SELECT CASE WHEN g.sub_rank_type = 'none'
                        THEN 0 ELSE gr.sub_rank_count END
            FROM gym_ranks gr
            JOIN gyms g ON g.gym_id = gr.gym_id
            WHERE gr.rank_id = CAST(:new_rank_id AS UUID)
        ) > 0 THEN 0
        ELSE NULL
    END
WHERE current_rank_id = CAST(:old_rank_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
