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
-- LIVE MEMBERSHIP means the contracted set the MRR tile, mrr_trend and
-- revenue_by_plan all use: a recurring-plan membership that has started
-- (start_date on or before gym-local today) and is not yet terminal (LEAST of
-- cancel_date / end_date, which skips NULLs). Freeze is ignored - it pauses
-- the bill, not the contract - so arpm's numerator is exactly the MRR tile.
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
        mm.member_id,
        mm.total_price,
        mm.quantity,
        pp.price AS list_price
    FROM member_memberships mm
    JOIN membership_plans p ON p.plan_id = mm.plan_id
    JOIN membership_plan_prices pp ON pp.price_id = mm.price_id
    CROSS JOIN gym_day gd
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND p.plan_type = 'recurring'
      AND mm.start_date <= gd.today
      AND (
          LEAST(mm.cancel_date, mm.end_date) IS NULL
          OR LEAST(mm.cancel_date, mm.end_date) > gd.today
      )
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
    -- Deliberately the identical test to revenue_hero's overdue segment, so
    -- the two overdue numbers on the Growth page can never disagree. Unlike
    -- the recurring tiles above it reads member_memberships_status, which
    -- drops a frozen membership, and it spans every plan type.
    SELECT COALESCE(sum(mms.total_price), 0)::bigint AS cents
    FROM member_memberships_status mms
    CROSS JOIN gym_day gd
    WHERE mms.gym_id = CAST(:gym_id AS UUID)
      AND mms.status = 'active'
      AND mms.next_due_date IS NOT NULL
      AND mms.next_due_date < gd.today
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
