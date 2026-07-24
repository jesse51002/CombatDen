-- Promotions (bars, count, monthly, all-time).
--
-- One bar per gym-local month from the month of the gym's first recorded
-- promotion through the current month. A promotion is a member_activities row
-- of type 'rank_changed' - the append-only activity feed is the only place a
-- rank change is dated, since members.current_rank_id holds no history.
--
-- The activity's timestamp column is named "time"; it is quoted because the
-- bare word is a type name.
--
-- A gym with no promotions yet emits an empty point list rather than a run of
-- zeroes: there is no series to draw.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
promos AS (
    SELECT
        date_trunc('month', (a."time" AT TIME ZONE gd.tz))::date AS month_start
    FROM member_activities a
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND a.activity_type = 'rank_changed'
),
bounds AS (
    SELECT
        gd.today,
        (SELECT min(p.month_start) FROM promos p) AS series_start
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
            FROM promos p
            WHERE p.month_start = mo.month_start
        )::bigint AS value
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'promotions',
            'label', 'Promotions',
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
