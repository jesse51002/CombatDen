-- Average Membership Length (line, count, monthly, all-time).
--
-- One series over the same all-time gym-local month grid the other lifecycle
-- lines use. A month's value is the AVERAGE membership length of the members
-- who held a LIVE membership as of that month's last day, where a member's
-- length is the whole months between their FIRST membership start_date and the
-- month's end. A rising line means the active base is staying longer.
--
-- LIVE as of the month end means a membership that had started by then
-- (start_date <= month_end) and had not gone terminal by then - its
-- LEAST(cancel_date, end_date) is null or still in the future relative to
-- month_end. A member with several live memberships in a month is one member
-- (deduped), measured from their FIRST membership across all their rows.
--
-- The month count is age()-derived, never a day count divided by 30, so
-- month-length and leap years cannot drift the boundaries - the same whole-
-- month arithmetic member_tenure uses. The average is rounded to one decimal:
-- the value is genuinely fractional (4.2 months), and the count formatter
-- keeps a single fraction digit for exactly this kind of average.
--
-- A month with zero live members is OMITTED, not plotted as 0 - the average of
-- an empty set is undefined, so the line keeps honest gaps rather than a
-- misleading floor.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
memberships AS (
    SELECT
        mm.member_id,
        mm.start_date,
        LEAST(mm.cancel_date, mm.end_date) AS term_date
    FROM member_memberships mm
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND mm.start_date IS NOT NULL
),
first_membership AS (
    SELECT
        m.member_id,
        min(m.start_date) AS first_start
    FROM memberships m
    GROUP BY m.member_id
),
bounds AS (
    SELECT
        gd.today,
        COALESCE(
            (SELECT min(m.start_date) FROM memberships m),
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
live_members AS (
    SELECT DISTINCT
        mo.month_start,
        mo.month_end,
        m.member_id,
        f.first_start
    FROM months mo
    JOIN memberships m
        ON m.start_date <= mo.month_end
       AND (m.term_date IS NULL OR m.term_date > mo.month_end)
    JOIN first_membership f ON f.member_id = m.member_id
),
month_avg AS (
    SELECT
        lm.month_start,
        round(
            avg(
                date_part('year', age(lm.month_end, lm.first_start)) * 12
                + date_part('month', age(lm.month_end, lm.first_start))
            )::numeric,
            1
        ) AS avg_len
    FROM live_members lm
    GROUP BY lm.month_start
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'avg_length',
            'label', 'Avg months',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(ma.month_start, 'YYYY-MM-DD'),
                            'value', ma.avg_len
                        )
                        ORDER BY ma.month_start
                    )
                    FROM month_avg ma
                ),
                '[]'::jsonb
            )
        )
    )
) AS data
