-- Retention (kpi_group) - four headline tiles about members leaving and
-- members sticking, all evaluated gym-local.
--
--   churn_30d     - members who crossed into dormancy in the trailing 30 days
--                   over the members who were still active when that window
--                   opened (percent). Compared against the 30 days before it,
--                   so the delta is in percentage POINTS.
--   at_risk       - members with a live membership whose last check-in is
--                   older than the at-risk window, or who have never checked
--                   in at all. Point-in-time, so no honest previous value.
--   retention_90d - of the members who were active 90 days ago, the share who
--                   have still not crossed into dormancy (percent). Also
--                   point-in-time, so no delta.
--   active_streaks- members on a LIVE weekly streak: at least one check-in in
--                   each of two CONSECUTIVE ISO weeks, where the later of the
--                   two is the current or the previous week (an older pair is
--                   a streak that already ended). Point-in-time, no delta.
--
-- The 30-day and 90-day spans are the metric's own definition (they are what
-- the tiles MEAN), not tunable behaviour, so they are literals; the dormancy
-- and at-risk windows are configured and therefore bound.
WITH
{dormant_cte},
bounds AS (
    SELECT
        gd.tz,
        gd.today,
        gd.today - 30 AS win_start,
        gd.today - 60 AS prev_win_start,
        gd.today - 90 AS ninety_start,
        date_trunc('week', gd.today)::date AS week0,
        (date_trunc('week', gd.today) - INTERVAL '1 week')::date AS week1,
        (date_trunc('week', gd.today) - INTERVAL '2 weeks')::date AS week2
    FROM gym_day gd
),
churn AS (
    SELECT
        count(*) FILTER (
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= b.win_start
              AND (NOT d.dormant OR d.dormant_since > b.win_start)
        )::numeric AS base_now,
        count(*) FILTER (
            WHERE d.dormant
              AND d.dormant_since > b.win_start
              AND d.dormant_since <= b.today
        )::numeric AS lost_now,
        count(*) FILTER (
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= b.prev_win_start
              AND (NOT d.dormant OR d.dormant_since > b.prev_win_start)
        )::numeric AS base_prev,
        count(*) FILTER (
            WHERE d.dormant
              AND d.dormant_since > b.prev_win_start
              AND d.dormant_since <= b.win_start
        )::numeric AS lost_prev
    FROM member_dormancy d
    CROSS JOIN bounds b
),
retention AS (
    SELECT
        count(*) FILTER (
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= b.ninety_start
              AND (NOT d.dormant OR d.dormant_since > b.ninety_start)
        )::numeric AS cohort_size,
        count(*) FILTER (
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= b.ninety_start
              AND (NOT d.dormant OR d.dormant_since > b.ninety_start)
              AND NOT d.dormant
        )::numeric AS still_here
    FROM member_dormancy d
    CROSS JOIN bounds b
),
active_members AS (
    SELECT DISTINCT mms.member_id
    FROM member_memberships_status mms
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
),
at_risk AS (
    SELECT count(*)::bigint AS at_risk_now
    FROM members m
    JOIN active_members am ON am.member_id = m.member_id
    CROSS JOIN bounds b
    WHERE m.gym_id = CAST(:gym_id AS UUID)
      AND (
          m.last_class IS NULL
          OR (m.last_class AT TIME ZONE b.tz)::date
             <= b.today - CAST(:at_risk_days AS INTEGER)
      )
),
streak_weeks AS (
    SELECT DISTINCT
        a.member_id,
        date_trunc('week', (a.occurred_at AT TIME ZONE b.tz))::date AS wk
    FROM member_attendance a
    CROSS JOIN bounds b
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (a.occurred_at AT TIME ZONE b.tz)::date >= b.week2
),
streak_flags AS (
    SELECT
        sw.member_id,
        bool_or(sw.wk = b.week0) AS in_week0,
        bool_or(sw.wk = b.week1) AS in_week1,
        bool_or(sw.wk = b.week2) AS in_week2
    FROM streak_weeks sw
    CROSS JOIN bounds b
    GROUP BY sw.member_id
),
streaks AS (
    SELECT count(*)::bigint AS live_streaks
    FROM streak_flags f
    WHERE (f.in_week0 AND f.in_week1)
       OR (f.in_week1 AND f.in_week2)
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'churn_30d',
            'label', 'Churn (30d)',
            'value', COALESCE(
                round(c.lost_now / NULLIF(c.base_now, 0) * 100, 1), 0
            ),
            'unit', 'percent',
            'delta_abs', CASE
                WHEN c.base_now > 0 AND c.base_prev > 0
                    THEN round(
                        c.lost_now / c.base_now * 100
                        - c.lost_prev / c.base_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'at_risk',
            'label', 'At Risk',
            'value', ar.at_risk_now,
            'unit', 'count'
        ),
        jsonb_build_object(
            'key', 'retention_90d',
            'label', 'Retention (90d)',
            'value', COALESCE(
                round(r.still_here / NULLIF(r.cohort_size, 0) * 100, 1), 0
            ),
            'unit', 'percent'
        ),
        jsonb_build_object(
            'key', 'active_streaks',
            'label', 'Active Streaks',
            'value', s.live_streaks,
            'unit', 'count'
        )
    )
) AS data
FROM churn c
CROSS JOIN retention r
CROSS JOIN at_risk ar
CROSS JOIN streaks s
