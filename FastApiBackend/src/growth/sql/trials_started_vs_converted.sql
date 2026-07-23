-- Started vs Converted (bars, count, monthly, all-time).
--
-- Two series over one gym-local month grid:
--   started   - trial memberships, bucketed by the month of their start_date
--   converted - members counted ONCE, in the month their FIRST 'recurring'
--               membership started, and only when they held a trial at or
--               before that start
--
-- The two grains differ on purpose. A gym can sell a member several trial
-- packs, and each sale is a real "started" event; a member can only convert
-- once, so counting their first recurring start keeps the converted bar from
-- double counting an upgrade or a plan change later on.
--
-- plan_type is a VARCHAR with a CHECK constraint, so it is compared as text.
-- Statuses are irrelevant here: a trial that was later cancelled still
-- started, and a conversion that later churned still converted.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
trials AS (
    SELECT
        mm.member_id,
        mm.start_date
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'trial'
      AND mm.start_date IS NOT NULL
),
first_recurring AS (
    SELECT
        mm.member_id,
        min(mm.start_date) AS start_date
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
      AND mm.start_date IS NOT NULL
    GROUP BY mm.member_id
),
conversions AS (
    SELECT
        fr.member_id,
        fr.start_date
    FROM first_recurring fr
    WHERE EXISTS (
        SELECT 1
        FROM trials t
        WHERE t.member_id = fr.member_id
          AND t.start_date <= fr.start_date
    )
),
bounds AS (
    SELECT
        gd.today,
        LEAST(
            COALESCE(
                (SELECT min(t.start_date) FROM trials t),
                gd.today
            ),
            COALESCE(
                (SELECT min(c.start_date) FROM conversions c),
                gd.today
            )
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
            FROM trials t
            WHERE t.start_date >= mo.month_start
              AND t.start_date < mo.next_month_start
        )::bigint AS started,
        (
            SELECT count(*)
            FROM conversions c
            WHERE c.start_date >= mo.month_start
              AND c.start_date < mo.next_month_start
        )::bigint AS converted
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'count',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'started',
            'label', 'Started',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.started
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'converted',
            'label', 'Converted',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.converted
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
