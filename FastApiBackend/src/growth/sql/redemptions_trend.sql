-- Reward Redemptions (bars, count, monthly, all-time).
--
-- One bar per gym-local month from the month of the gym's first APPROVED
-- redemption through the current month.
--
-- Only 'approved' rows count, and they are bucketed by resolved_at - the
-- moment staff granted the reward. A pending request may still be rejected and
-- a rejected one was never granted, so neither is a redemption; bucketing on
-- requested_at would date an approval to a month in which nothing was given.
--
-- A gym that has never approved a redemption emits an empty point list rather
-- than a run of zeroes.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
approved AS (
    SELECT
        date_trunc(
            'month', (r.resolved_at AT TIME ZONE gd.tz)
        )::date AS month_start
    FROM member_reward_redemptions r
    CROSS JOIN gym_day gd
    WHERE r.gym_id = CAST(:gym_id AS UUID)
      AND r.status = 'approved'
      AND r.resolved_at IS NOT NULL
),
bounds AS (
    SELECT
        gd.today,
        (SELECT min(a.month_start) FROM approved a) AS series_start
    FROM gym_day gd
),
months AS (
    SELECT gs.month_ts::date AS month_start
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
            FROM approved a
            WHERE a.month_start = mo.month_start
        )::bigint AS value
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'redemptions',
            'label', 'Redemptions',
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
