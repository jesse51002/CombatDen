-- Check-ins (bars, count, weekly, all-time).
--
-- One series, one point per gym-local ISO week from the week of the gym's
-- first check-in through the current week. Weeks are keyed on their Monday
-- (date_trunc('week', ...) is ISO, so Monday is week start) computed from
-- occurred_at converted to the gym's local date - the denormalized effective
-- start instant is the right bucket key, and UTC would slide a late-evening
-- check-in into the wrong week.
--
-- Check-ins with a NULL plan_id / item_id are staff check-ins with no
-- covering membership; they are real attendance and stay counted.
--
-- by_class repeats the same weekly grid per class, which is what the
-- Attendance tab's class filter draws. Only classes that have at least one
-- check-in appear - an empty flat line for a class nobody attends is noise.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
att AS (
    SELECT
        a.class_id,
        date_trunc(
            'week', (a.occurred_at AT TIME ZONE gd.tz)::date
        )::date AS week_start
    FROM member_attendance a
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
),
class_att AS (
    SELECT
        a.week_start,
        c.class_id,
        c.class_name
    FROM att a
    JOIN gym_classes c ON c.class_id = a.class_id
),
bounds AS (
    SELECT
        date_trunc('week', gd.today)::date AS last_week,
        COALESCE(
            (SELECT min(a.week_start) FROM att a),
            date_trunc('week', gd.today)::date
        ) AS first_week
    FROM gym_day gd
),
weeks AS (
    SELECT gs.week_ts::date AS week_start
    FROM bounds b
    CROSS JOIN generate_series(
        b.first_week::timestamp,
        b.last_week::timestamp,
        INTERVAL '1 week'
    ) AS gs(week_ts)
),
points AS (
    SELECT
        w.week_start,
        (
            SELECT count(*)
            FROM att a
            WHERE a.week_start = w.week_start
        )::bigint AS value
    FROM weeks w
),
class_points AS (
    SELECT
        cl.class_id,
        cl.class_name,
        w.week_start,
        count(ca.class_id)::bigint AS value
    FROM (SELECT DISTINCT class_id, class_name FROM class_att) cl
    CROSS JOIN weeks w
    LEFT JOIN class_att ca
        ON ca.class_id = cl.class_id
       AND ca.week_start = w.week_start
    GROUP BY cl.class_id, cl.class_name, w.week_start
),
class_series AS (
    SELECT
        cp.class_id,
        cp.class_name,
        jsonb_agg(
            jsonb_build_object(
                'date', to_char(cp.week_start, 'YYYY-MM-DD'),
                'value', cp.value
            )
            ORDER BY cp.week_start
        ) AS series_points
    FROM class_points cp
    GROUP BY cp.class_id, cp.class_name
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'week',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'checkins',
            'label', 'Check-ins',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.week_start, 'YYYY-MM-DD'),
                            'value', p.value
                        )
                        ORDER BY p.week_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        )
    ),
    'by_class', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'class_id', CAST(cs.class_id AS TEXT),
                    'class_name', cs.class_name,
                    'series', jsonb_build_array(
                        jsonb_build_object(
                            'key', 'checkins',
                            'label', 'Check-ins',
                            'points', cs.series_points
                        )
                    )
                )
                ORDER BY cs.class_name
            )
            FROM class_series cs
        ),
        '[]'::jsonb
    )
) AS data
