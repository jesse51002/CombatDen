-- Assign the gym's lowest-ordered rank to every rank-less member and
-- append one 'rank_changed' audit row per backfilled member in the
-- same statement (:activity_type is bound to RANK_CHANGED_ACTIVITY_TYPE),
-- so each member's progress anchor starts at the backfill moment rather
-- than their join date. The member is pinned to the lowest rank's BASE
-- leaf: current_sub_index 0 when it has sub-ranks, else NULL. The leaf's
-- display name is Python-derived and bound as :new_rank_name (the gym's
-- sub_rank_type drives the label). A gym with no ranks yields an empty
-- `lowest` CTE, making the whole statement a no-op.
WITH lowest AS (
    SELECT rank_id, sub_rank_count
    FROM gym_ranks
    WHERE gym_id = CAST(:gym_id AS UUID)
    ORDER BY main_rank_num_order ASC
    LIMIT 1
),
backfilled AS (
    UPDATE members m
    SET current_rank_id = lowest.rank_id,
        current_sub_index = CASE
            WHEN lowest.sub_rank_count > 0 THEN 0
            ELSE NULL
        END
    FROM lowest
    WHERE m.gym_id = CAST(:gym_id AS UUID)
      AND m.current_rank_id IS NULL
    RETURNING
        m.member_id,
        lowest.rank_id AS new_rank_id
)
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
SELECT
    b.member_id,
    CAST(:gym_id AS UUID),
    :activity_type,
    jsonb_build_object(
        'old_rank_id', NULL,
        'new_rank_id', b.new_rank_id,
        'old_rank_name', NULL,
        'new_rank_name', CAST(:new_rank_name AS TEXT)
    )
FROM backfilled b
