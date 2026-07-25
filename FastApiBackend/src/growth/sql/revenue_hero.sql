-- Monthly Revenue (hero_split, cents) for the CURRENT gym-local month.
--
-- Three segments summing to the hero total:
--   collected - net succeeded cash this month (payments are positive, refunds
--               negative, so a plain SUM is already "collected minus refunds")
--   overdue   - net price of active memberships whose due date has passed
--   expected  - net price of active recurring memberships still due this month
--
-- Money always comes from member_memberships.total_price, the POST-discount
-- per-membership price the payment sync writes back. Discount math is never
-- re-derived here.
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
        date_trunc('month', gd.today)::date AS month_start,
        (date_trunc('month', gd.today) + INTERVAL '1 month')::date
            AS next_month_start
    FROM gym_day gd
),
collected AS (
    SELECT COALESCE(sum(c.amount), 0)::bigint AS cents
    FROM member_charges c
    CROSS JOIN bounds b
    WHERE c.gym_id = CAST(:gym_id AS UUID)
      AND c.status = 'succeeded'
      AND (c.charge_time AT TIME ZONE b.tz)::date >= b.month_start
      AND (c.charge_time AT TIME ZONE b.tz)::date < b.next_month_start
),
overdue AS (
    SELECT COALESCE(sum(mms.total_price), 0)::bigint AS cents
    FROM member_memberships_status mms
    CROSS JOIN bounds b
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND ({is_overdue})
),
expected AS (
    SELECT COALESCE(sum(mms.total_price), 0)::bigint AS cents
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    CROSS JOIN bounds b
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
      AND p.plan_type = 'recurring'
      AND mms.next_due_date IS NOT NULL
      AND mms.next_due_date >= b.today
      AND mms.next_due_date < b.next_month_start
)
SELECT jsonb_build_object(
    'total', c.cents + o.cents + e.cents,
    'unit', 'cents',
    'caption', to_char(b.month_start, 'FMMonth YYYY'),
    'segments', jsonb_build_array(
        jsonb_build_object(
            'key', 'collected',
            'label', 'Collected',
            'value', c.cents,
            'tone', 'positive'
        ),
        jsonb_build_object(
            'key', 'overdue',
            'label', 'Overdue',
            'value', o.cents,
            'tone', 'negative'
        ),
        jsonb_build_object(
            'key', 'expected',
            'label', 'Expected',
            'value', e.cents,
            'tone', 'neutral'
        )
    )
) AS data
FROM bounds b
CROSS JOIN collected c
CROSS JOIN overdue o
CROSS JOIN expected e
