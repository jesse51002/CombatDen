-- Revenue Quality (kpi_group) - four point-in-time tiles about the SHAPE of
-- the gym's revenue rather than its size. All four are snapshots of right now,
-- so none of them carries a delta: there is no stored history of open invoices
-- or of what the discount rate was 30 days ago, and inventing one from current
-- rows would be a guess presented as a comparison.
--
--   arpm            - average net revenue per paying member: the recurring
--                     run-rate over the members carrying it.
--   discount_rate   - the share of list price the gym is giving away.
--   open_invoices   - money billed and not yet paid.
--   overdue_amount  - the price of memberships whose due date has passed.
--
-- ONE RULE FOR "WHO IS CURRENTLY PAYING US", identical to revenue_hero, the
-- MRR tile and revenue_by_plan: a recurring-plan membership that has STARTED
-- (start_date on or before gym-local today) and whose derived status on
-- member_memberships_status is 'active' - which drops cancelled, ended AND
-- FROZEN rows. A frozen membership is not billed (the sync prices it as a
-- 100%-off subscription), so it is neither revenue nor a paying member here.
-- Nobody re-splits this rule: arpm's numerator is exactly the MRR tile, and
-- its denominator counts only members that tile is charging.
--
-- THE DISCOUNT RATE COMPARES TWO STORED NUMBERS. total_price is the
-- POST-discount price the payment sync wrote back; membership_plan_prices.price
-- is the list price of the exact pinned price version. The rate is
-- (list - net) / list, and NOTHING here replays discount math - no applied
-- discount rows, no coupon percentages. A hand-rolled replay would drift from
-- what Stripe actually bills, which is the one number that matters.
-- Both sides of that ratio are summed over the SAME inner-joined rows, so a
-- membership whose price version is not visible cannot skew the ratio by
-- landing in one side of it only.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
live_recurring AS (
    SELECT
        mms.member_id,
        mms.total_price,
        mms.quantity,
        pp.price AS list_price
    FROM member_memberships_status mms
    JOIN membership_plans p ON p.plan_id = mms.plan_id
    JOIN membership_plan_prices pp ON pp.price_id = mms.price_id
    CROSS JOIN gym_day gd
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
      AND mms.status = 'active'
      AND mms.start_date <= gd.today
),
recurring_totals AS (
    SELECT
        COALESCE(sum(lr.total_price), 0)::bigint AS net_cents,
        COALESCE(sum(lr.list_price * lr.quantity), 0)::bigint AS list_cents,
        count(DISTINCT lr.member_id)::bigint AS paying_members
    FROM live_recurring lr
),
open_invoices AS (
    SELECT COALESCE(sum(i.total_amount), 0)::bigint AS cents
    FROM member_invoices i
    WHERE i.gym_id = CAST(:gym_id AS UUID)
      AND i.status = 'open'
),
overdue AS (
    -- The shared overdue predicate (src/shared/sql/membership_overdue.sql,
    -- injected as the is_overdue template variable) — literally the same
    -- text as revenue_hero's
    -- overdue segment and the members-list Overdue tab, so the two overdue
    -- numbers on the Growth page can never disagree. It spans every plan type
    -- and keys off next_due_date rather than start_date, unlike the recurring
    -- tiles above.
    SELECT COALESCE(sum(mms.total_price), 0)::bigint AS cents
    FROM member_memberships_status mms
    CROSS JOIN gym_day gd
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND ({is_overdue})
)
SELECT jsonb_build_object(
    'tiles', jsonb_build_array(
        jsonb_build_object(
            'key', 'arpm',
            'label', 'Revenue per Member',
            'value', COALESCE(
                round(
                    r.net_cents::numeric / NULLIF(r.paying_members, 0)
                ),
                0
            ),
            'unit', 'cents'
        ),
        jsonb_build_object(
            'key', 'discount_rate',
            'label', 'Discount Rate',
            'value', COALESCE(
                round(
                    (r.list_cents - r.net_cents)::numeric
                    / NULLIF(r.list_cents, 0) * 100,
                    1
                ),
                0
            ),
            'unit', 'percent'
        ),
        jsonb_build_object(
            'key', 'open_invoices',
            'label', 'Open Invoices',
            'value', oi.cents,
            'unit', 'cents'
        ),
        jsonb_build_object(
            'key', 'overdue_amount',
            'label', 'Overdue',
            'value', ov.cents,
            'unit', 'cents'
        )
    )
) AS data
FROM recurring_totals r
CROSS JOIN open_invoices oi
CROSS JOIN overdue ov
