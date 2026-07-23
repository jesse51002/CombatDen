-- Trials (kpi_group) - four headline tiles about the trial funnel.
--
-- A TRIAL is a membership whose plan_type is 'trial'; a CONVERSION is that
-- same member later holding a 'recurring' membership that started on or
-- after their trial started. plan_type is a VARCHAR with a CHECK constraint,
-- so it is compared as text.
--
--   active_trials  - live trial memberships right now (point-in-time: there
--                    is no honest previous-window equivalent, so its delta
--                    is deliberately null)
--   started_30d    - trials that started in the last 30 gym-local days,
--                    against the 30 days before that
--   converted_30d  - members holding a LIVE recurring membership that
--                    started in the last 30 days and who held a trial at or
--                    before that start
--   conversion_90d - of the trials STARTED in the last 90 days, the share
--                    that has converted since. Its delta is null on purpose:
--                    an older 90-day cohort has had strictly more time to
--                    convert, so the two rates are not comparable.
--
-- Statuses come from member_memberships_status (the view that derives
-- active / cancelled / ended / frozen); the underlying rows are read through
-- member_memberships, never the unfiltered table.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
trials AS (
    SELECT
        mms.member_id,
        mms.start_date,
        mms.status
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'trial'
),
recurring AS (
    SELECT
        mms.member_id,
        mms.start_date,
        mms.status
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
),
live AS (
    SELECT count(*)::bigint AS active_trials
    FROM trials t
    WHERE t.status = 'active'
),
started AS (
    SELECT
        count(*) FILTER (
            WHERE t.start_date > gd.today - 30
        )::bigint AS s30,
        count(*) FILTER (
            WHERE t.start_date > gd.today - 60
              AND t.start_date <= gd.today - 30
        )::bigint AS s30_prev
    FROM trials t
    CROSS JOIN gym_day gd
),
converted AS (
    SELECT
        count(DISTINCT r.member_id) FILTER (
            WHERE r.start_date > gd.today - 30
        )::bigint AS c30,
        count(DISTINCT r.member_id) FILTER (
            WHERE r.start_date > gd.today - 60
              AND r.start_date <= gd.today - 30
        )::bigint AS c30_prev
    FROM recurring r
    CROSS JOIN gym_day gd
    WHERE r.status = 'active'
      AND EXISTS (
          SELECT 1
          FROM trials t
          WHERE t.member_id = r.member_id
            AND t.start_date <= r.start_date
      )
),
cohort_90 AS (
    SELECT
        t.member_id,
        min(t.start_date) AS trial_start
    FROM trials t
    CROSS JOIN gym_day gd
    WHERE t.start_date > gd.today - 90
    GROUP BY t.member_id
),
conversion_90 AS (
    SELECT
        count(*)::bigint AS cohort_size,
        count(*) FILTER (
            WHERE EXISTS (
                SELECT 1
                FROM recurring r
                WHERE r.member_id = c.member_id
                  AND r.start_date >= c.trial_start
            )
        )::bigint AS converted_size
    FROM cohort_90 c
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'active_trials',
            'label', 'Active Trials',
            'value', l.active_trials,
            'unit', 'count'
        ),
        jsonb_build_object(
            'key', 'started_30d',
            'label', 'Started (30d)',
            'value', s.s30,
            'unit', 'count',
            'delta_abs', s.s30 - s.s30_prev,
            'delta_pct', CASE
                WHEN s.s30_prev > 0
                    THEN round(
                        (s.s30 - s.s30_prev)::numeric / s.s30_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'converted_30d',
            'label', 'Converted (30d)',
            'value', cv.c30,
            'unit', 'count',
            'delta_abs', cv.c30 - cv.c30_prev,
            'delta_pct', CASE
                WHEN cv.c30_prev > 0
                    THEN round(
                        (cv.c30 - cv.c30_prev)::numeric
                        / cv.c30_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'conversion_90d',
            'label', 'Conversion (90d)',
            'value', COALESCE(
                round(
                    c9.converted_size::numeric
                    / NULLIF(c9.cohort_size, 0) * 100, 1
                ),
                0
            ),
            'unit', 'percent'
        )
    )
) AS data
FROM live l
CROSS JOIN started s
CROSS JOIN converted cv
CROSS JOIN conversion_90 c9
