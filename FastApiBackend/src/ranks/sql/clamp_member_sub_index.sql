-- Re-fit members' current_sub_index to a rank whose sub_rank_count just
-- shrank: a new count of 0 clears the sub-index (the rank is now its own
-- leaf), otherwise clamp to the new top leaf (new_count - 1). Runs in the
-- same transaction as the sub_rank_count update. The sub_rank_image_overrides
-- map is deliberately left untouched (persist-only) — dormant overrides for
-- now-hidden indices reactivate if the count grows back.
UPDATE members
SET current_sub_index = CASE
        WHEN :new_count = 0 THEN NULL
        ELSE LEAST(current_sub_index, :new_count - 1)
    END
WHERE gym_id = CAST(:gym_id AS UUID)
  AND current_rank_id = CAST(:rank_id AS UUID)
  AND current_sub_index IS NOT NULL
