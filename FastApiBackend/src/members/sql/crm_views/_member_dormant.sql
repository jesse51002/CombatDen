-- Canonical DORMANT derivation for the CRM members list.
--
-- It is a self-contained correlated BOOLEAN expression, not a CTE: the same
-- text is injected as a SELECT column (all_view.sql), as a scalar-subquery
-- predicate (total_counts.sql), and as a WHERE predicate (the members-list
-- status filter). One text, so the badge, the tally, and the filter can never
-- disagree about who is dormant. It joins its own members / gyms rows, so the
-- only thing it needs from the outer query is the two id expressions supplied
-- as the structural template variables member_id and gym_id.
--
-- Binds used here: the dormancy window in days.
--
-- A member is DORMANT for this surface when ALL THREE hold:
--   1. they hold at least one LIVE (active or frozen) membership, AND
--   2. EVERY live membership is on a trial / one_time plan (no live
--      recurring one), AND
--   3. their last ACTIVITY is older than the dormancy window.
--
-- Condition 2 is an aggregate over ALL of the member's memberships, which is
-- why this is a grouped subquery and not a per-row test: the members list
-- returns one row per plan, so a member holding a live recurring membership
-- AND a live trial pack must never be dormant on the strength of the trial
-- row alone.
--
-- SCOPE: unlike the analytics rule this mirrors, a member whose memberships
-- are ALL terminal is NOT dormant here. The list already labels them
-- cancelled / ended, which is accurate and is a distinction staff rely on.
-- The analytics side deliberately counts both as churn -- see
-- src/growth/sql/_dormant_members.sql, the canonical reference for the
-- shared parts of this rule. Keep the two in agreement.
--
-- THE NEVER-ATTENDED GUARD (do not "simplify" this away). Condition 3's
-- activity date is GREATEST(last check-in, newest LIVE membership start),
-- never the check-in alone:
--   * A bare "no check-in means dormant" test would brand someone who bought
--     a trial pack YESTERDAY and simply has not come in yet as gone quiet on
--     day one -- a false positive on the newest and most valuable leads.
--     Falling back to the pack's start gives them the full window to show up.
--   * Taking the LATER of the two (not just a null fallback) means buying a
--     fresh pack RESTARTS the clock even when the previous check-in is old:
--     a returning member is not dormant the moment they re-buy.
-- GREATEST ignores NULLs, and condition 1 guarantees a live membership, so
-- the live start date is always there as the floor.
--
-- The two type families differ on purpose: members.last_class is TIMESTAMPTZ
-- and start_date is DATE, so the timestamp is converted to a gym-local DATE
-- before the comparison and both sides are dates. Every date here is
-- gym-local, never a bare UTC one.
EXISTS (
    SELECT 1
    FROM members dm
    JOIN gyms dg ON dg.gym_id = dm.gym_id
    JOIN member_memberships_status dmm
        ON dmm.member_id = dm.member_id
        AND dmm.gym_id = dm.gym_id
    JOIN membership_plans dmp
        ON dmp.plan_id = dmm.plan_id
        AND dmp.gym_id = dmm.gym_id
    WHERE dm.member_id = {member_id}
        AND dm.gym_id = {gym_id}
    GROUP BY dm.member_id, dm.last_class, dg.timezone
    HAVING
        count(*) FILTER (
            WHERE dmm.status IN ('active', 'frozen')
        ) > 0
        AND count(*) FILTER (
            WHERE dmm.status IN ('active', 'frozen')
            AND dmp.plan_type = 'recurring'
        ) = 0
        AND GREATEST(
            (dm.last_class AT TIME ZONE dg.timezone)::date,
            max(dmm.start_date) FILTER (
                WHERE dmm.status IN ('active', 'frozen')
            )
        ) < (now() AT TIME ZONE dg.timezone)::date
            - CAST(:dormancy_days AS INTEGER)
)
