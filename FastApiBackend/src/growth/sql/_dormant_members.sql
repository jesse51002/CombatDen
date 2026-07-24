-- Canonical DORMANT / lost-member derivation, shared by every membership
-- lifecycle metric. It is injected as a structural template variable, so it is
-- a CTE BODY: no leading WITH, no trailing comma. A consumer writes
--
--     WITH
--     <this fragment>,
--     more_ctes AS (...)
--     SELECT ...
--
-- The two CTEs consumers actually read are gym_day (the gym-local today +
-- timezone) and member_dormancy (one row per member of the gym). The rest
-- (membership_terms, membership_rollup, member_activity) are internal steps.
--
-- Binds used here: the gym id, and the dormancy window in days.
--
-- A member is DORMANT when they hold at least one membership AND either
--   (a) every membership they hold is terminal (cancelled or ended), or
--   (b) every non-terminal membership they hold is on a trial / one_time plan
--       AND their last ACTIVITY is older than the dormancy window.
-- A member with NO membership rows at all is never dormant - unenrolled is a
-- different thing from lost.
--
-- THE NEVER-ATTENDED GUARD (do not "simplify" this away). Case (b)'s activity
-- date is GREATEST(last check-in, latest LIVE membership start), never the
-- check-in alone:
--   * A bare "last_class IS NULL means dormant" test would brand someone who
--     bought a trial pack YESTERDAY and simply has not come in yet as lost on
--     day one - a false positive on the newest and most valuable leads, the
--     exact opposite of what this metric is for. Falling back to the pack's
--     start date gives them the full window to show up.
--   * Taking the LATER of the two (not just a null fallback) means buying a
--     fresh pack RESTARTS the clock even when the previous check-in is old:
--     a returning member is not dormant the moment they re-buy.
-- GREATEST ignores NULLs, and case (b) only fires when a live membership
-- exists, so the live start date is always there as the floor.
--
-- The two type families differ on purpose: members.last_class is TIMESTAMPTZ
-- and start_date is DATE, so the timestamp is converted to a gym-local DATE
-- before the comparison and both sides are dates.
--
-- dormant_since is the gym-local date they crossed into dormancy: the last
-- terminal date for (a), or the day the activity gap exceeded the window for
-- (b). Every "became dormant during period X" metric filters on it, so the
-- rule is written once and the periods differ only in their bounds.
gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
membership_terms AS (
    SELECT
        mm.member_id,
        mm.start_date,
        LEAST(mm.cancel_date, mm.end_date) AS term_date,
        p.plan_type,
        (
            LEAST(mm.cancel_date, mm.end_date) IS NOT NULL
            AND LEAST(mm.cancel_date, mm.end_date) <= gd.today
        ) AS is_terminal
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    CROSS JOIN gym_day gd
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
),
membership_rollup AS (
    SELECT
        t.member_id,
        min(t.start_date) AS first_start,
        count(*) AS membership_count,
        count(*) FILTER (WHERE t.is_terminal) AS terminal_count,
        max(t.term_date) FILTER (WHERE t.is_terminal) AS last_terminal_date,
        count(*) FILTER (
            WHERE NOT t.is_terminal AND t.plan_type = 'recurring'
        ) AS live_recurring_count,
        -- The floor of case (b)'s activity date: the newest still-live pack.
        max(t.start_date) FILTER (
            WHERE NOT t.is_terminal
        ) AS latest_live_start
    FROM membership_terms t
    GROUP BY t.member_id
),
member_activity AS (
    SELECT
        m.member_id,
        r.first_start,
        r.membership_count,
        r.terminal_count,
        r.last_terminal_date,
        r.live_recurring_count,
        -- The never-attended guard: the LATER of the last check-in and the
        -- newest live pack's start (GREATEST skips NULLs).
        GREATEST(
            (m.last_class AT TIME ZONE gd.tz)::date,
            r.latest_live_start
        ) AS last_activity,
        gd.today
    FROM members m
    LEFT JOIN membership_rollup r ON r.member_id = m.member_id
    CROSS JOIN gym_day gd
    WHERE m.gym_id = CAST(:gym_id AS UUID)
),
member_dormancy AS (
    SELECT
        a.member_id,
        a.first_start,
        (
            COALESCE(a.membership_count, 0) > 0
            AND (
                a.terminal_count = a.membership_count
                OR (
                    a.live_recurring_count = 0
                    AND a.last_activity
                        < a.today - CAST(:dormancy_days AS INTEGER)
                )
            )
        ) AS dormant,
        -- Case (b) ONLY: the member still HAS a live membership (not all
        -- terminal) but it is only trial/one_time packs and they have gone
        -- quiet. This is the "dormant" the members list LABELS dormant -- an
        -- all-terminal member is "cancelled"/"ended" there, not dormant.
        -- The broader `dormant` above (which also fires on all-terminal) is
        -- the churn/lost unit; a bucket that LABELS members "dormant" must use
        -- THIS flag so the word means the same thing on both surfaces.
        (
            COALESCE(a.membership_count, 0) > 0
            AND a.terminal_count < a.membership_count
            AND a.live_recurring_count = 0
            AND a.last_activity < a.today - CAST(:dormancy_days AS INTEGER)
        ) AS dormant_unused_pack,
        CASE
            WHEN a.terminal_count = a.membership_count
                THEN a.last_terminal_date
            ELSE a.last_activity + CAST(:dormancy_days AS INTEGER)
        END AS dormant_since
    FROM member_activity a
)
