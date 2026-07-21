-- Conversion Rate (line, percent, monthly, all-time) - for each month's
-- trial COHORT, the share of it that has since converted to a recurring
-- membership.
--
-- A member belongs to the cohort of the month their FIRST trial started, so
-- a member who buys three trial packs is one cohort member, not three. They
-- count as converted once they hold any 'recurring' membership that started
-- on or after that first trial start - regardless of whether that membership
-- has since been cancelled, because the conversion still happened.
--
-- ONLY MATURED COHORTS ARE PLOTTED. The maturity window is 60 days measured
-- from the END of the cohort month, so every trial in a plotted month has
-- had at least 60 days - and the earliest ones about 90 - to convert. The
-- number is chosen against how trials actually run here: trial plans are
-- days-to-weeks long, and the decision to sign up lands during the pack or
-- shortly after it lapses. A month whose members have not had that long is
-- EXCLUDED, never reported as a low rate: an immature cohort's 0% is a
-- measurement artefact, and drawing it would show a cliff at the right edge
-- of the chart every single month.
--
-- Months with no trials at all are also omitted rather than plotted as 0% -
-- a conversion rate of an empty cohort is undefined, not zero. The line
-- therefore has gaps, which is honest.
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
recurring AS (
    SELECT
        mm.member_id,
        mm.start_date
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
      AND mm.start_date IS NOT NULL
),
cohort AS (
    SELECT
        t.member_id,
        min(t.start_date) AS trial_start
    FROM trials t
    GROUP BY t.member_id
),
cohort_months AS (
    SELECT
        date_trunc('month', c.trial_start)::date AS month_start,
        count(*)::bigint AS cohort_size,
        count(*) FILTER (
            WHERE EXISTS (
                SELECT 1
                FROM recurring r
                WHERE r.member_id = c.member_id
                  AND r.start_date >= c.trial_start
            )
        )::bigint AS converted_size
    FROM cohort c
    GROUP BY date_trunc('month', c.trial_start)::date
),
matured AS (
    SELECT
        cm.month_start,
        COALESCE(
            round(
                cm.converted_size::numeric
                / NULLIF(cm.cohort_size, 0) * 100, 1
            ),
            0
        ) AS rate
    FROM cohort_months cm
    CROSS JOIN gym_day gd
    WHERE (cm.month_start + INTERVAL '1 month' + INTERVAL '60 days')::date
          <= gd.today
)
SELECT jsonb_build_object(
    'unit', 'percent',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'conversion',
            'label', 'Conversion Rate',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(m.month_start, 'YYYY-MM-DD'),
                            'value', m.rate
                        )
                        ORDER BY m.month_start
                    )
                    FROM matured m
                ),
                '[]'::jsonb
            )
        )
    )
) AS data
