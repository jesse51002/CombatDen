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
--   avg_length    - current average membership length: over members who hold
--                   a LIVE membership right now, the average whole-months
--                   since their FIRST membership started. The point-in-time
--                   snapshot of the Average Membership Length line; a higher
--                   number means members are staying longer. No delta.
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
avg_length AS (
    -- Over members holding a live membership as of today, the average
    -- whole-months since their FIRST membership start. age()-based whole
    -- months, mirroring member_tenure.sql / avg_membership_length.sql.
    SELECT round(avg(pm.months)::numeric, 1) AS avg_months
    FROM (
        SELECT
            mm.member_id,
            extract(year FROM age(b.today, min(mm.start_date)))::int * 12
            + extract(month FROM age(b.today, min(mm.start_date)))::int
                AS months
        FROM member_memberships mm
        CROSS JOIN bounds b
        WHERE mm.gym_id = CAST(:gym_id AS UUID)
          AND EXISTS (
              SELECT 1
              FROM member_memberships live
              WHERE live.member_id = mm.member_id
                AND live.gym_id = mm.gym_id
                AND live.start_date <= b.today
                AND (
                    LEAST(live.cancel_date, live.end_date) IS NULL
                    OR LEAST(live.cancel_date, live.end_date) > b.today
                )
          )
        GROUP BY mm.member_id, b.today
    ) pm
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
            'key', 'avg_membership_length',
            'label', 'Avg Membership Length',
            'value', COALESCE(al.avg_months, 0),
            'unit', 'count'
        )
    )
) AS data
FROM churn c
CROSS JOIN retention r
CROSS JOIN at_risk ar
CROSS JOIN avg_length al
