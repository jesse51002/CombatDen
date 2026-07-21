-- Members Over Time (line, count, monthly, all-time).
--
-- One series, one point per gym-local month from the month of the gym's first
-- membership through the current month. A month's value is the number of
-- members who held a live membership as of that month's last day and had not
-- yet crossed into dormancy by then - the same canonical rule the KPI tiles
-- and the churn donuts use, evaluated against a historical date instead of
-- today.
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
        (gs.month_ts + INTERVAL '1 month' - INTERVAL '1 day')::date
            AS month_end
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
            WHERE d.first_start IS NOT NULL
              AND d.first_start <= mo.month_end
              AND (NOT d.dormant OR d.dormant_since > mo.month_end)
        )::bigint AS value
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'active',
            'label', 'Active Members',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.value
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
