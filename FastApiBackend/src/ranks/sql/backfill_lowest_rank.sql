-- Assign the gym's lowest-ordered rank to every rank-less member and
-- append one 'rank_changed' audit row per backfilled member in the
-- same statement (:activity_type is bound to MemberActivityType.rank_changed),
-- so each member's progress anchor starts at the backfill moment rather
-- than their join date. The member is pinned to the lowest rank's BASE
-- leaf: current_sub_index 0 when it has sub-ranks, else NULL. The EFFECTIVE
-- sub-rank count is 0 whenever the gym's sub_rank_type is 'none' (sub-ranks
-- disabled gym-wide), so a 'none' gym pins the base leaf as NULL. The leaf's
-- display name is Python-derived and bound as :new_rank_name (the gym's
-- sub_rank_type drives the label). A gym with no ranks yields an empty
-- `lowest` CTE, making the whole statement a no-op.
--
-- A backfill has NO "from" leaf — nobody was promoted out of anything — so
-- every old_* key in the payload is a literal NULL. Never fabricate an old
-- belt where there isn't one: the member app renders the from-side only when
-- it is present.
--
-- The new belt image is Python-derived and bound as :new_image_url, resolved
-- through the domain's single image rule (RanksBase._leaf_image_url — the base
-- leaf's override, else the main rank's image) from the same ladder read that
-- produced :new_rank_name. It is a SNAPSHOT on purpose: gym_ranks.image_url is
-- user-writable, so re-uploading belt art must not retroactively change what a
-- past rank change looked like. The new sub-index comes from the UPDATE's own
-- RETURNING, so the payload records exactly the leaf that was written.
WITH lowest AS (
    SELECT
        gr.rank_id,
        CASE WHEN g.sub_rank_type = 'none'
             THEN 0 ELSE gr.sub_rank_count END AS sub_rank_count
    FROM gym_ranks gr
    JOIN gyms g ON g.gym_id = gr.gym_id
    WHERE gr.gym_id = CAST(:gym_id AS UUID)
    ORDER BY gr.main_rank_num_order ASC
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
        lowest.rank_id AS new_rank_id,
        m.current_sub_index AS new_sub_index
)
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
SELECT
    b.member_id,
    CAST(:gym_id AS UUID),
    CAST(:activity_type AS member_activity_type),
    jsonb_build_object(
        'old_rank_id', NULL,
        'new_rank_id', b.new_rank_id,
        'old_rank_name', NULL,
        'new_rank_name', CAST(:new_rank_name AS TEXT),
        'old_sub_index', NULL,
        'new_sub_index', b.new_sub_index,
        'old_image_url', NULL,
        'new_image_url', CAST(:new_image_url AS TEXT)
    )
FROM backfilled b
