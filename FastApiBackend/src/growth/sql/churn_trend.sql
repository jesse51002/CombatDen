-- Churn Rate (line, percent, monthly, all-time).
--
-- One series over the same all-time month grid members_trend and
-- members_gained_lost use. A month's value is the share of the OPENING base --
-- members who joined before the month and were still active when it OPENED --
-- who crossed into dormancy during it. Numerator AND denominator are both
-- restricted to that opening cohort, so the ratio is always in [0, 100]. A
-- member who joined AND went dormant inside the SAME month is a raw "lost"
-- count on Gained vs Lost but is deliberately NOT part of this rate's cohort
-- (they were never in the opening base), so a churn-rate point and a
-- Gained-vs-Lost bar MAY differ by exactly those same-month joiners -- a rate
-- needs a matching cohort, a count does not.
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
            WHERE d.first_start IS NOT NULL
              AND d.first_start < mo.month_start
              AND (NOT d.dormant OR d.dormant_since >= mo.month_start)
        )::numeric AS base,
        (
            SELECT count(*)
            FROM member_dormancy d
            WHERE d.dormant
              -- Restrict the numerator to the SAME opening cohort as `base`:
              -- a member who joined during the month was never in the base,
              -- so counting their churn against it would push the rate > 100%.
              AND d.first_start IS NOT NULL
              AND d.first_start < mo.month_start
              AND d.dormant_since >= mo.month_start
              AND d.dormant_since < mo.next_month_start
        )::numeric AS lost
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'percent',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'churn',
            'label', 'Churn Rate',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', COALESCE(
                                round(p.lost / NULLIF(p.base, 0) * 100, 1), 0
                            )
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
