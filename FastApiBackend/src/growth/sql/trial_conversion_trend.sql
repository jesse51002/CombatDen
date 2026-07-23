-- Conversion Rate (line, percent, monthly, all-time) - the share of each
-- month's RESOLVED trial members that converted to a recurring membership,
-- anchored on when the trial ENDED rather than when it started.
--
-- A member's trial is RESOLVED once it has ended AND a grace week has passed:
-- their trial terminal date - LEAST(cancel_date, end_date) taken over their
-- trial memberships, using the LATEST such date because they stay "on trial"
-- until their last trial ends - is non-null and at least 7 days in the past.
-- A member whose trial has not ended, or ended less than a week ago, is NOT
-- yet resolved and is excluded: the sign-up decision usually lands during the
-- pack or in the days just after it lapses, so a grace week lets that outcome
-- settle before the member is counted. The 7-day grace is hardcoded here, like
-- the other fixed trial windows in this domain.
--
-- A member is one cohort member however many trials they bought (the min /
-- max rollup below collapses them). They count as CONVERTED once they hold any
-- 'recurring' membership whose start_date is on or after their FIRST trial
-- start - regardless of whether that recurring membership has since been
-- cancelled, because the conversion still happened.
--
-- Each resolved member is bucketed by the MONTH their trial ended, and a
-- month's rate is converted / resolved within that month. Only months with at
-- least one resolved member get a point: the rate of an empty month is
-- undefined, not zero, so the line keeps honest gaps rather than plotting 0%.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
trials AS (
    SELECT
        mm.member_id,
        mm.start_date,
        LEAST(mm.cancel_date, mm.end_date) AS term_date
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
member_trials AS (
    SELECT
        t.member_id,
        min(t.start_date) AS first_trial_start,
        max(t.term_date) AS trial_end
    FROM trials t
    GROUP BY t.member_id
),
resolved AS (
    SELECT
        mt.member_id,
        mt.first_trial_start,
        mt.trial_end
    FROM member_trials mt
    CROSS JOIN gym_day gd
    WHERE mt.trial_end IS NOT NULL
      -- The grace week: the outcome is only counted once the trial has been
      -- over for 7 days. Hardcoded like the other trial windows here.
      AND (mt.trial_end + INTERVAL '7 days')::date <= gd.today
),
end_months AS (
    SELECT
        date_trunc('month', r.trial_end)::date AS month_start,
        count(*)::bigint AS resolved_size,
        count(*) FILTER (
            WHERE EXISTS (
                SELECT 1
                FROM recurring rc
                WHERE rc.member_id = r.member_id
                  AND rc.start_date >= r.first_trial_start
            )
        )::bigint AS converted_size
    FROM resolved r
    GROUP BY date_trunc('month', r.trial_end)::date
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
                            'date', to_char(em.month_start, 'YYYY-MM-DD'),
                            'value', round(
                                em.converted_size::numeric
                                / NULLIF(em.resolved_size, 0) * 100, 1
                            )
                        )
                        ORDER BY em.month_start
                    )
                    FROM end_months em
                ),
                '[]'::jsonb
            )
        )
    )
) AS data
