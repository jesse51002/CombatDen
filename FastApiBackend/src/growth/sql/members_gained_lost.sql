-- Gained vs Lost (bars, count, monthly, all-time).
--
-- Two series over the same month grid as members_trend:
--   gained - members whose FIRST membership started in that month
--   lost   - members who crossed into dormancy in that month
-- Both read the canonical dormancy CTE, so "lost" here and "lost" on the KPI
-- tile can never disagree.
WITH
{dormant_cte},
bounds AS (
    SELECT
        gd.today,
        COALESCE(
            (SELECT min(d.first_start) FROM member_dormancy d),
            gd.today
        ) AS series_start
    FROM gym_day gd
),
months AS (
    SELECT
        gs.month_ts::date AS month_start,
        (gs.month_ts + INTERVAL '1 month')::date AS next_month_start
    FROM bounds b
    CROSS JOIN generate_series(
        date_trunc('month', b.series_start::timestamp),
        date_trunc('month', b.today::timestamp),
        INTERVAL '1 month'
    ) AS gs(month_ts)
),
points AS (
    SELECT
        mo.month_start,
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.first_start >= mo.month_start
              AND d.first_start < mo.next_month_start
        )::bigint AS gained,
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.dormant
              AND d.dormant_since >= mo.month_start
              AND d.dormant_since < mo.next_month_start
        )::bigint AS lost
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'gained',
            'label', 'Gained',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.gained
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'lost',
            'label', 'Lost',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.lost
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        )
    )
) AS data
