-- Trial Outcomes (breakdown, count) - what became of every trial started in
-- the last 90 gym-local days.
--
-- The cohort is DISTINCT MEMBERS with a trial that started in the window,
-- keyed on their earliest such trial. Each cohort member is classified into
-- exactly ONE bucket, in this priority order:
--
--   converted    - they hold a 'recurring' membership that started on or
--                  after that trial start (the conversion happened, whether
--                  or not it has since been cancelled)
--   lost         - not converted, and DORMANT by the canonical shared rule
--                  injected below - the same derivation every other
--                  lifecycle metric reads, so "lost" here can never disagree
--                  with "lost" on the Members tiles
--   still_active - everything else: not converted and not yet dormant, i.e.
--                  the trial is running or has just lapsed and the member is
--                  still inside the dormancy window
--
-- INVARIANT: the three buckets are mutually exclusive and exhaustive, so
-- converted + lost + still_active always equals the cohort size. The CASE
-- below is the only classifier, which is what guarantees it. All three
-- buckets are always emitted, at 0 when empty, so the breakdown does not
-- change shape as a gym's funnel moves.
--
-- The 90-day window is the metric's definition, not tunable behaviour; the
-- dormancy window IS tunable and arrives as a bind.
WITH
{dormant_cte},
trial_cohort AS (
    SELECT
        mm.member_id,
        min(mm.start_date) AS trial_start
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    CROSS JOIN gym_day gd
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'trial'
      AND mm.start_date IS NOT NULL
      AND mm.start_date > gd.today - 90
    GROUP BY mm.member_id
),
classified AS (
    SELECT
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM member_memberships r
                JOIN membership_plans rp ON rp.plan_id = r.plan_id
                WHERE r.member_id = c.member_id
                  AND r.gym_id = CAST(:gym_id AS UUID)
                  AND rp.plan_type = 'recurring'
                  AND r.start_date >= c.trial_start
            ) THEN 'converted'
            WHEN COALESCE(d.dormant, false) THEN 'lost'
            ELSE 'still_active'
        END AS outcome
    FROM trial_cohort c
    LEFT JOIN member_dormancy d ON d.member_id = c.member_id
),
buckets AS (
    SELECT
        b.outcome_key,
        b.outcome_label,
        b.sort_order,
        count(cl.outcome)::bigint AS value
    FROM (VALUES
        ('converted', 'Converted', 1),
        ('still_active', 'Still Active', 2),
        ('lost', 'Lost', 3)
    ) AS b(outcome_key, outcome_label, sort_order)
    LEFT JOIN classified cl ON cl.outcome = b.outcome_key
    GROUP BY b.outcome_key, b.outcome_label, b.sort_order
)
SELECT jsonb_build_object(
    'unit', 'count',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', bk.outcome_key,
                    'label', bk.outcome_label,
                    'value', bk.value
                )
                ORDER BY bk.sort_order
            )
            FROM buckets bk
        ),
        '[]'::jsonb
    )
) AS data
