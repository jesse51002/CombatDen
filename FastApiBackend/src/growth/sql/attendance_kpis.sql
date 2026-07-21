-- Attendance (kpi_group) - four headline tiles over trailing gym-local
-- windows, each compared against the immediately preceding window of the
-- same length.
--
--   checkins_7d        - check-ins in the last 7 gym-local days
--   checkins_30d       - check-ins in the last 30 gym-local days
--   active_members_30d - distinct members who checked in in that window
--   no_show_rate_30d   - reservations for an occurrence that has already
--                        passed whose member never checked in, over all
--                        such reservations in the window
--
-- Every attendance window buckets on occurred_at (the denormalized effective
-- start instant) converted to the gym's local date - never on the row's
-- created time and never on UTC. Rows whose plan_id / item_id are NULL are
-- staff check-ins with no covering membership; they are still real
-- attendance, so they are deliberately NOT filtered out.
--
-- A sign-up is a RESERVATION, not attendance, so the no-show test joins
-- class_signups to member_attendance on the FULL occurrence identity (class,
-- original date, original time) plus the member. Only occurrences that have
-- already passed are judged - a reservation for a future class cannot be a
-- no-show yet, so counting it would drag the rate down for no reason.
--
-- The no-show tile's delta is percentage POINTS (delta_abs). A percentage
-- change of a percentage is not a number anyone reads, so its delta_pct is
-- deliberately null. The tile windows are the metric's definition, not
-- tunable behaviour.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
att AS (
    SELECT
        a.member_id,
        (a.occurred_at AT TIME ZONE gd.tz)::date AS local_date,
        gd.today
    FROM member_attendance a
    CROSS JOIN gym_day gd
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (a.occurred_at AT TIME ZONE gd.tz)::date > gd.today - 60
),
checkins AS (
    SELECT
        count(*) FILTER (
            WHERE a.local_date > a.today - 7
        )::bigint AS c7,
        count(*) FILTER (
            WHERE a.local_date > a.today - 14
              AND a.local_date <= a.today - 7
        )::bigint AS c7_prev,
        count(*) FILTER (
            WHERE a.local_date > a.today - 30
        )::bigint AS c30,
        count(*) FILTER (
            WHERE a.local_date > a.today - 60
              AND a.local_date <= a.today - 30
        )::bigint AS c30_prev
    FROM att a
),
actives AS (
    SELECT
        count(DISTINCT a.member_id) FILTER (
            WHERE a.local_date > a.today - 30
        )::bigint AS m30,
        count(DISTINCT a.member_id) FILTER (
            WHERE a.local_date > a.today - 60
              AND a.local_date <= a.today - 30
        )::bigint AS m30_prev
    FROM att a
),
reservations AS (
    SELECT
        s.original_date,
        gd.today,
        EXISTS (
            SELECT 1
            FROM member_attendance a
            WHERE a.member_id = s.member_id
              AND a.class_id = s.class_id
              AND a.original_date = s.original_date
              AND a.original_time = s.original_time
        ) AS attended
    FROM class_signups s
    CROSS JOIN gym_day gd
    WHERE s.gym_id = CAST(:gym_id AS UUID)
      AND s.original_date < gd.today
      AND s.original_date > gd.today - 60
),
no_shows AS (
    SELECT
        count(*) FILTER (
            WHERE r.original_date > r.today - 30
        )::bigint AS booked30,
        count(*) FILTER (
            WHERE r.original_date > r.today - 30
              AND NOT r.attended
        )::bigint AS missed30,
        count(*) FILTER (
            WHERE r.original_date <= r.today - 30
        )::bigint AS booked30_prev,
        count(*) FILTER (
            WHERE r.original_date <= r.today - 30
              AND NOT r.attended
        )::bigint AS missed30_prev
    FROM reservations r
),
rates AS (
    SELECT
        COALESCE(
            round(n.missed30::numeric / NULLIF(n.booked30, 0) * 100, 1),
            0
        ) AS rate30,
        CASE
            WHEN n.booked30_prev > 0
                THEN round(
                    n.missed30_prev::numeric / n.booked30_prev * 100, 1)
        END AS rate30_prev
    FROM no_shows n
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'checkins_7d',
            'label', 'Check-ins (7d)',
            'value', c.c7,
            'unit', 'count',
            'delta_abs', c.c7 - c.c7_prev,
            'delta_pct', CASE
                WHEN c.c7_prev > 0
                    THEN round(
                        (c.c7 - c.c7_prev)::numeric / c.c7_prev * 100, 1)
            END,
            'compare_label', 'vs prior 7 days'
        ),
        jsonb_build_object(
            'key', 'checkins_30d',
            'label', 'Check-ins (30d)',
            'value', c.c30,
            'unit', 'count',
            'delta_abs', c.c30 - c.c30_prev,
            'delta_pct', CASE
                WHEN c.c30_prev > 0
                    THEN round(
                        (c.c30 - c.c30_prev)::numeric / c.c30_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'active_members_30d',
            'label', 'Active Members (30d)',
            'value', ac.m30,
            'unit', 'count',
            'delta_abs', ac.m30 - ac.m30_prev,
            'delta_pct', CASE
                WHEN ac.m30_prev > 0
                    THEN round(
                        (ac.m30 - ac.m30_prev)::numeric
                        / ac.m30_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'no_show_rate_30d',
            'label', 'No-show Rate (30d)',
            'value', r.rate30,
            'unit', 'percent',
            'delta_abs', r.rate30 - r.rate30_prev,
            'compare_label', 'vs prior 30 days'
        )
    )
) AS data
FROM checkins c
CROSS JOIN actives ac
CROSS JOIN rates r
