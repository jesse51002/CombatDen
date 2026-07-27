-- The member's MOST RECENT rank change, returned ONLY when that change was a
-- genuine PROMOTION — with BOTH belts already resolved.
--
-- This is what drives the member app's promotion animation. The app shows it
-- once per new promotion, keyed on its own local "promotion watermark" (the
-- same seed-silently-on-null pattern as the celebration watermark), so the
-- server's only job is to answer "has the member just moved UP, and what did
-- BOTH belts look like" — the client never has to remember or infer a
-- previous rank.
--
-- WHY THERE IS A FILTER AT ALL. member_activities records EVERY rank change
-- faithfully — staff corrections, demotions and unassignments included — so
-- the newest rank_changed row is not necessarily something to celebrate. The
-- app's copy reads "You've been promoted", and congratulating a member on a
-- demotion is worse than showing no animation at all, so a change that cannot
-- be PROVEN to move the member UP yields no row and the app simply stays
-- quiet. Fail closed, always.
--
-- THIS IS A READ-SIDE FILTER ONLY. src/ranks/sql/insert_rank_activity.sql (and
-- backfill_lowest_rank.sql) must keep logging every rank change, promotion or
-- not — the activity log is the audit trail AND the progress anchor that
-- member_details / ready-to-promote count classes from. Do NOT "fix" the
-- writer to skip demotions. Only this read has an opinion about celebration.
--
-- THE ORDERING RULE. A leaf is (main rank ladder position, sub-index), and a
-- promotion is a strictly GREATER leaf under that pair, compared left to right
--
--   1. main rank — gym_ranks.main_rank_num_order ASC is the ladder, 0-based
--      and lower-is-lower. It is the order list_ranks.sql reads, the order
--      RanksBase._next_leaf walks to find the next rank up, and the order
--      backfill_lowest_rank.sql calls "lowest" (ORDER BY ... ASC LIMIT 1).
--      A higher position ALWAYS outranks a lower one whatever the sub-indices
--      are, because the pair compares left to right.
--   2. sub-index — within one main rank, current_sub_index ASC (0 is the bare
--      belt, higher is more stripes / a higher division), which is exactly the
--      direction _next_leaf advances. A stripe promotion is therefore a real
--      promotion even though the main rank never changed.
--
-- The ladder position is the ONE thing read live from gym_ranks, because it is
-- the one thing the payload does not carry. Everything the app RENDERS — both
-- display names, both belt images — still comes straight out of the activity's
-- own snapshot, never from this join, since image_url and
-- sub_rank_image_overrides are user-writable and re-uploading belt art must not
-- retroactively change what a past promotion looked like. The tradeoff of
-- reading position live is that re-ordering the ladder can change whether an
-- OLD change still reads as a promotion; that is preferable to celebrating
-- against a ladder that no longer exists.
--
-- WHAT YIELDS NO ROW, and why
--   * an unassignment — new_rank_id is NULL, so it has no leaf to be above;
--   * a demotion or a lateral/no-op correction — the new leaf is not strictly
--     greater;
--   * a rank that has since been DELETED from the ladder on either side — its
--     position is unknowable, so the comparison cannot be proven;
--   * a LEGACY row whose main rank did not change. Rows written before the
--     payload carried sub-indices have only the 4 original keys, so a
--     same-main-rank change could equally be a stripe promotion or a stripe
--     demotion. Unprovable means no celebration. A legacy row that DID change
--     main rank is still fully provable from its rank ids and does surface —
--     nothing is backfilled to rescue the rest.
--
-- A FIRST assignment (old_rank_id NULL — the gym's lowest-rank backfill, or
-- staff giving a rank-less member their first belt) has no FROM leaf to be
-- above and DOES surface, as an arrival the app renders without a from-side.
--
-- ONLY THE NEWEST CHANGE IS EVER CONSIDERED. The newest row is selected first
-- and the promotion test applied to it; an earlier promotion is never reached
-- back for. If a promotion was later corrected downward, the member no longer
-- holds that belt — the profile already shows the belt they DO hold, and
-- re-celebrating a superseded one would be a second wrong answer.
--
-- Scoped by member_id alone, which is already gym-scoped: member_activities
-- carries a composite FK on (member_id, gym_id) into members, and a member row
-- belongs to exactly one gym, so every activity of this member is at this
-- member's gym. The ladder join re-uses that same gym_id. The caller has
-- already passed verify_member_self on the path gym.
--
-- LIMIT 1 over a DESC time ordering; activity_id breaks a same-instant tie so
-- the answer is deterministic.
WITH latest_change AS (
    SELECT
        a.activity_id,
        a.time AS promoted_at,
        a.gym_id,
        a.activity_info
    FROM member_activities a
    WHERE a.member_id = CAST(:member_id AS UUID)
      AND a.activity_type = 'rank_changed'
    ORDER BY a.time DESC, a.activity_id DESC
    LIMIT 1
),
leaves AS (
    SELECT
        c.activity_id,
        c.promoted_at,
        c.activity_info ->> 'old_rank_name' AS old_rank_name,
        c.activity_info ->> 'new_rank_name' AS new_rank_name,
        c.activity_info ->> 'old_image_url' AS old_image_url,
        c.activity_info ->> 'new_image_url' AS new_image_url,
        c.activity_info ->> 'old_rank_id' AS old_rank_id,
        CAST(c.activity_info ->> 'old_sub_index' AS INTEGER) AS old_sub_index,
        CAST(c.activity_info ->> 'new_sub_index' AS INTEGER) AS new_sub_index,
        old_rank.main_rank_num_order AS old_ladder_position,
        new_rank.main_rank_num_order AS new_ladder_position
    FROM latest_change c
    LEFT JOIN gym_ranks old_rank
        ON old_rank.gym_id = c.gym_id
       AND old_rank.rank_id = CAST(c.activity_info ->> 'old_rank_id' AS UUID)
    LEFT JOIN gym_ranks new_rank
        ON new_rank.gym_id = c.gym_id
       AND new_rank.rank_id = CAST(c.activity_info ->> 'new_rank_id' AS UUID)
)
SELECT
    activity_id,
    promoted_at,
    old_rank_name,
    new_rank_name,
    old_image_url,
    new_image_url
FROM leaves
WHERE new_ladder_position IS NOT NULL
  AND (
        old_rank_id IS NULL
        OR new_ladder_position > old_ladder_position
        OR (
            new_ladder_position = old_ladder_position
            AND old_sub_index IS NOT NULL
            AND new_sub_index IS NOT NULL
            AND new_sub_index > old_sub_index
        )
      );
