-- Monthly Churn (donut_pair, percent 0-100).
--
--   last_30     - members who crossed into dormancy in the trailing 30 days,
--                 over the members who were still active when that window
--                 opened
--   gym_average - the mean of the trailing 12 completed months' churn values
--
-- The 30-day and 12-month spans are the metric's own definition (they are what
-- the two donuts MEAN), not tunable behaviour, so they are literals here
-- rather than binds.
WITH
{dormant_cte},
bounds AS (
    SELECT
        gd.today,
        gd.today - 30 AS window_start,
        date_trunc('month', gd.today::timestamp) AS month_start_ts
    FROM gym_day gd
),
last_30 AS (
    SELECT
        count(*) FILTER (
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= b.window_start
              AND (NOT d.dormant OR d.dormant_since > b.window_start)
        )::numeric AS base,
        count(*) FILTER (
            WHERE d.dormant
              AND d.dormant_since > b.window_start
              AND d.dormant_since <= b.today
        )::numeric AS lost
    FROM member_dormancy d
    CROSS JOIN bounds b
),
months AS (
    SELECT
        gs.month_ts::date AS month_start,
        (gs.month_ts + INTERVAL '1 month')::date AS next_month_start
    FROM bounds b
    CROSS JOIN generate_series(
        b.month_start_ts - INTERVAL '12 months',
        b.month_start_ts - INTERVAL '1 month',
        INTERVAL '1 month'
    ) AS gs(month_ts)
),
monthly AS (
    SELECT
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.first_start IS NOT NULL
              AND d.first_start < mo.month_start
              AND (NOT d.dormant OR d.dormant_since >= mo.month_start)
        )::numeric AS base,
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.dormant
              AND d.dormant_since >= mo.month_start
              AND d.dormant_since < mo.next_month_start
        )::numeric AS lost
    FROM months mo
)
SELECT jsonb_build_object(
    'donuts', jsonb_build_array(
        jsonb_build_object(
            'key', 'last_30',
            'label', 'Last 30 Days',
            'pct', CASE
                WHEN l.base > 0 THEN round(l.lost / l.base * 100, 1)
                ELSE 0
            END,
            'caption', l.lost::bigint || ' of ' || l.base::bigint
                       || ' members'
        ),
        jsonb_build_object(
            'key', 'gym_average',
            'label', '12-Month Average',
            'pct', COALESCE(
                (
                    SELECT round(
                        avg(
                            CASE
                                WHEN mn.base > 0
                                    THEN mn.lost / mn.base * 100
                            END
                        ), 1)
                    FROM monthly mn
                ),
                0
            ),
            'caption', 'Mean monthly churn'
        )
    )
) AS data
FROM last_30 l
