-- Reconcile every member's current_sub_index to the gym's NEW sub_rank_type
-- so the leaf invariant (effective sub_rank_count > 0 <=> sub_index NOT NULL)
-- stays valid after the gym flips its style, WITHOUT a destructive rewrite:
--   * target 'none'  -> every member's sub_index becomes NULL (the gym has
--     main belts but no sub-positions; the per-rank sub_rank_count and
--     sub_rank_image_overrides are left intact and reactivate on a switch
--     back).
--   * target 'stripes'/'div', member on a rank with sub_rank_count > 0 ->
--     ensure a valid leaf: a NULL sub_index (coming FROM 'none') becomes the
--     base leaf 0; an already-valid in-range index is preserved (a pure
--     stripes<->div switch is only a re-label, never a member move); a
--     stray out-of-range index is clamped to the top leaf.
--   * target 'stripes'/'div', member on a subless rank -> NULL.
-- Rank-less members (current_rank_id IS NULL) never match the join, so they
-- stay NULL. sub_rank_count / sub_rank_image_overrides are never touched.
UPDATE members m
SET current_sub_index = CASE
        WHEN CAST(:sub_rank_type AS sub_rank_type) = 'none' THEN NULL
        WHEN gr.sub_rank_count = 0 THEN NULL
        WHEN m.current_sub_index IS NULL THEN 0
        ELSE LEAST(m.current_sub_index, gr.sub_rank_count - 1)
    END
FROM gym_ranks gr
WHERE m.current_rank_id = gr.rank_id
  AND m.gym_id = gr.gym_id
  AND m.gym_id = CAST(:gym_id AS UUID)
