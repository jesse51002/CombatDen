-- Sign-ups vs Check-ins (bars, count, weekly, all-time).
--
-- Two series over one gym-local ISO week grid (keyed on the Monday), so the
-- gap between them IS the no-show gap:
--   signups  - reservations, bucketed by the OCCURRENCE day they reserve
--              (original_date, already a gym-local calendar date)
--   checkins - attendance, bucketed by occurred_at converted to the gym's
--              local date
-- Both therefore land on the week the class actually ran, which is the only
-- way the two bars are comparable.
--
-- A sign-up is a RESERVATION, never attendance: a signed-up member who never
-- checks in stays in the signups series only. Nothing here infers one from
-- the other.
--
-- Reservations for an occurrence that has NOT happened yet are excluded, and
-- the week grid stops at the current week. A gym books days ahead, so
-- charting future reservations would draw a tall sign-up bar against a
-- structurally empty check-in bar every single week - a no-show cliff that
-- is really just the future. Both series therefore run through today.
--
-- by_class repeats both series per class, powering the Attendance tab's class
-- filter. Only classes with at least one sign-up or check-in appear.
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
sign_ups AS (
    SELECT
        s.class_id,
        date_trunc('week', s.original_date)::date AS week_start
    FROM class_signups s
    CROSS JOIN gym_day gd
    WHERE s.gym_id = CAST(:gym_id AS UUID)
      AND s.original_date <= gd.today
),
bounds AS (
    SELECT
        date_trunc('week', gd.today)::date AS last_week,
        LEAST(
            COALESCE(
                (SELECT min(a.week_start) FROM att a),
                date_trunc('week', gd.today)::date
            ),
            COALESCE(
                (SELECT min(s.week_start) FROM sign_ups s),
                date_trunc('week', gd.today)::date
            )
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
            FROM sign_ups s
            WHERE s.week_start = w.week_start
        )::bigint AS signups,
        (
            SELECT count(*)
            FROM att a
            WHERE a.week_start = w.week_start
        )::bigint AS checkins
    FROM weeks w
),
classes_seen AS (
    SELECT DISTINCT c.class_id, c.class_name
    FROM gym_classes c
    WHERE c.gym_id = CAST(:gym_id AS UUID)
      AND (
          EXISTS (SELECT 1 FROM att a WHERE a.class_id = c.class_id)
          OR EXISTS (SELECT 1 FROM sign_ups s WHERE s.class_id = c.class_id)
      )
),
class_points AS (
    SELECT
        cl.class_id,
        cl.class_name,
        w.week_start,
        (
            SELECT count(*)
            FROM sign_ups s
            WHERE s.class_id = cl.class_id
              AND s.week_start = w.week_start
        )::bigint AS signups,
        (
            SELECT count(*)
            FROM att a
            WHERE a.class_id = cl.class_id
              AND a.week_start = w.week_start
        )::bigint AS checkins
    FROM classes_seen cl
    CROSS JOIN weeks w
),
class_series AS (
    SELECT
        cp.class_id,
        cp.class_name,
        jsonb_agg(
            jsonb_build_object(
                'date', to_char(cp.week_start, 'YYYY-MM-DD'),
                'value', cp.signups
            )
            ORDER BY cp.week_start
        ) AS signup_points,
        jsonb_agg(
            jsonb_build_object(
                'date', to_char(cp.week_start, 'YYYY-MM-DD'),
                'value', cp.checkins
            )
            ORDER BY cp.week_start
        ) AS checkin_points
    FROM class_points cp
    GROUP BY cp.class_id, cp.class_name
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'week',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'signups',
            'label', 'Sign-ups',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.week_start, 'YYYY-MM-DD'),
                            'value', p.signups
                        )
                        ORDER BY p.week_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'checkins',
            'label', 'Check-ins',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.week_start, 'YYYY-MM-DD'),
                            'value', p.checkins
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
                            'key', 'signups',
                            'label', 'Sign-ups',
                            'points', cs.signup_points
                        ),
                        jsonb_build_object(
                            'key', 'checkins',
                            'label', 'Check-ins',
                            'points', cs.checkin_points
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
