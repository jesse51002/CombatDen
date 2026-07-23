-- Revenue (kpi_group) - four headline money tiles over the trailing 30
-- gym-local days, each compared against the 30 days before them.
--
--   collected_30d - net succeeded cash. Payments are positive and refunds
--                   negative in member_charges, so a plain SUM is already
--                   "collected minus refunds" (same rule as revenue_hero).
--   mrr           - the current net monthly recurring run-rate, and the same
--                   run-rate as it stood 30 days ago.
--   refunds_30d   - money handed back, reported as a POSITIVE magnitude (the
--                   stored amounts are negative, so the sum is negated).
--   failed_30d    - failed charge attempts. A count, not money: each retry is
--                   its own row, so this is attempts, not distinct members.
--
-- ONE RULE FOR "WHO IS CURRENTLY PAYING US", shared by revenue_hero,
-- revenue_by_plan and the revenue-quality tiles: a recurring-plan membership
-- that has STARTED (start_date on or before gym-local today) and whose derived
-- status on member_memberships_status is 'active'. That view drops cancelled,
-- ended AND FROZEN rows. A FROZEN membership is not billed at all - the sync
-- prices it as a 100%-off subscription - so counting its contracted price as
-- revenue overstates the number. Nothing on the Revenue tab may re-split this
-- rule: the hero, this tile, the per-plan breakdown and ARPM are all the same
-- set of memberships.
--
-- Money always comes from member_memberships.total_price, the POST-discount
-- per-membership price the payment sync writes back. Discount math is never
-- re-derived here. The one honesty caveat that buys: total_price is a CURRENT
-- snapshot, so the 30-days-ago run-rate prices the old membership set at
-- today's prices. It moves with who was enrolled, not with repricing.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
bounds AS (
    SELECT
        gd.tz,
        gd.today,
        gd.today - 30 AS window_start,
        gd.today - 60 AS prev_window_start
    FROM gym_day gd
),
succeeded AS (
    SELECT
        COALESCE(sum(c.amount) FILTER (
            WHERE (c.charge_time AT TIME ZONE b.tz)::date > b.window_start
        ), 0)::bigint AS collected_now,
        COALESCE(sum(c.amount) FILTER (
            WHERE (c.charge_time AT TIME ZONE b.tz)::date <= b.window_start
        ), 0)::bigint AS collected_prev,
        -COALESCE(sum(c.amount) FILTER (
            WHERE c.kind = 'refund'
              AND (c.charge_time AT TIME ZONE b.tz)::date > b.window_start
        ), 0)::bigint AS refunds_now,
        -COALESCE(sum(c.amount) FILTER (
            WHERE c.kind = 'refund'
              AND (c.charge_time AT TIME ZONE b.tz)::date <= b.window_start
        ), 0)::bigint AS refunds_prev
    FROM member_charges c
    CROSS JOIN bounds b
    WHERE c.gym_id = CAST(:gym_id AS UUID)
      AND c.status = 'succeeded'
      AND (c.charge_time AT TIME ZONE b.tz)::date > b.prev_window_start
      AND (c.charge_time AT TIME ZONE b.tz)::date <= b.today
),
failed AS (
    SELECT
        count(*) FILTER (
            WHERE (c.charge_time AT TIME ZONE b.tz)::date > b.window_start
        )::bigint AS failed_now,
        count(*) FILTER (
            WHERE (c.charge_time AT TIME ZONE b.tz)::date <= b.window_start
        )::bigint AS failed_prev
    FROM member_charges c
    CROSS JOIN bounds b
    WHERE c.gym_id = CAST(:gym_id AS UUID)
      AND c.status = 'failed'
      AND (c.charge_time AT TIME ZONE b.tz)::date > b.prev_window_start
      AND (c.charge_time AT TIME ZONE b.tz)::date <= b.today
),
mrr AS (
    -- The 30-days-ago comparison re-runs the SAME rule as of the earlier
    -- date - started by then, not terminal by then, not frozen then - by
    -- unrolling the view's own derivation against window_start instead of
    -- today. The freeze test reads the view's freeze_start_date /
    -- freeze_end_date columns, which are the member's CURRENT freeze window:
    -- a freeze that has already ENDED is not stored anywhere, so the earlier
    -- point can only honour a freeze that is still running now. Evaluated at
    -- today this expression is exactly status = 'active'.
    SELECT
        COALESCE(sum(mms.total_price) FILTER (
            WHERE mms.status = 'active'
              AND mms.start_date <= b.today
        ), 0)::bigint AS mrr_now,
        COALESCE(sum(mms.total_price) FILTER (
            WHERE mms.start_date <= b.window_start
              AND (
                  LEAST(mms.cancel_date, mms.end_date) IS NULL
                  OR LEAST(mms.cancel_date, mms.end_date) > b.window_start
              )
              AND NOT (
                  mms.freeze_start_date IS NOT NULL
                  AND mms.freeze_end_date IS NOT NULL
                  AND mms.freeze_start_date <= b.window_start
                  AND b.window_start <= mms.freeze_end_date
              )
        ), 0)::bigint AS mrr_prev
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    CROSS JOIN bounds b
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'collected_30d',
            'label', 'Collected (30d)',
            'value', s.collected_now,
            'unit', 'cents',
            'delta_abs', s.collected_now - s.collected_prev,
            'delta_pct', CASE
                WHEN s.collected_prev > 0
                    THEN round(
                        (s.collected_now - s.collected_prev)::numeric
                        / s.collected_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'mrr',
            'label', 'Recurring Revenue',
            'value', m.mrr_now,
            'unit', 'cents',
            'delta_abs', m.mrr_now - m.mrr_prev,
            'delta_pct', CASE
                WHEN m.mrr_prev > 0
                    THEN round(
                        (m.mrr_now - m.mrr_prev)::numeric
                        / m.mrr_prev * 100, 1)
            END,
            'compare_label', 'vs 30 days ago'
        ),
        jsonb_build_object(
            'key', 'refunds_30d',
            'label', 'Refunded (30d)',
            'value', s.refunds_now,
            'unit', 'cents',
            'delta_abs', s.refunds_now - s.refunds_prev,
            'delta_pct', CASE
                WHEN s.refunds_prev > 0
                    THEN round(
                        (s.refunds_now - s.refunds_prev)::numeric
                        / s.refunds_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        ),
        jsonb_build_object(
            'key', 'failed_30d',
            'label', 'Failed Charges (30d)',
            'value', f.failed_now,
            'unit', 'count',
            'delta_abs', f.failed_now - f.failed_prev,
            'delta_pct', CASE
                WHEN f.failed_prev > 0
                    THEN round(
                        (f.failed_now - f.failed_prev)::numeric
                        / f.failed_prev * 100, 1)
            END,
            'compare_label', 'vs prior 30 days'
        )
    )
) AS data
FROM succeeded s
CROSS JOIN failed f
CROSS JOIN mrr m
