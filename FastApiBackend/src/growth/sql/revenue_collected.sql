-- Recurring vs One-time (bars, cents, monthly, all-time).
--
-- Two grouped-bar series over the gym-local months from the gym's first
-- succeeded charge through the current month: the recurring-plan share and the
-- one-time/trial share of the money that ACTUALLY moved each month. Only
-- succeeded charges count; refunds are stored NEGATIVE, so a plain SUM is
-- already net of refunds.
--
-- THE NEWEST BAR IS PARTIAL - the current month is still in progress, so it
-- counts only the charges that have landed so far.
--
-- WHY CHARGES AND NOT MEMBERSHIP DATES: a FROZEN member is not billed, so their
-- contracted price must not count as revenue. Only the CURRENT freeze window is
-- stored (members.freeze_start_date / freeze_end_date) - a freeze that has
-- already ended leaves no trace - so no membership-date reconstruction could
-- honour that rule for any month but the newest. A charge is the freeze rule
-- encoded permanently: a frozen member simply generates none.
--
-- ATTRIBUTION - a charge pays a whole INVOICE, which can mix recurring
-- membership lines with one-time / trial / custom ones, so each portion is
-- attributed separately. Each succeeded charge is apportioned by its invoice's
-- line items:
--
--     recurring_share = SUM(recurring membership line amounts)
--                       / SUM(all recorded line amounts)
--     one_time_share  = SUM(one_time/trial membership line amounts)
--                       / SUM(all recorded line amounts)
--
-- and the charge's own amount carries each share. recurring + one_time +
-- non-membership shares therefore reconstruct the whole charge. The denominator
-- is the RECORDED LINE TOTAL rather than member_invoices.total_amount on
-- purpose: invoice-level discounts make the two differ, and a fully-recurring
-- invoice must attribute 100% of the cash that actually moved, whatever the
-- list lines summed to. Refunds ride the same invoice, are stored NEGATIVE, and
-- get the same share, so a plain SUM is already net of refunds.
--
-- AN INVOICE WITH NO RECORDED LINES COUNTS AS FULLY RECURRING (never one-time).
-- The invoice webhook deliberately skips proration lines, so a purely-prorated
-- invoice (a mid-cycle start, upgrade or plan change) stores real money with no
-- lines at all. Prorations only ever arise on a subscription, so that money is
-- recurring; dropping it would silently understate every month in which a
-- membership changed mid-cycle. One-time and trial invoices always keep their
-- lines and so are never caught by this branch - the one-time series only ever
-- counts real one_time/trial line items.
--
-- revenue_trend's line plots ALL revenue (this recurring share PLUS the
-- one-time share PLUS any non-membership cash) over the SAME month grid, so the
-- two charge-derived charts share an x-axis exactly; this Recurring series is
-- the recurring slice of that total, never the whole line.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
invoice_split AS (
    SELECT
        li.invoice_id,
        sum(li.amount)::numeric AS recorded_cents,
        COALESCE(sum(li.amount) FILTER (
            WHERE li.item_type = 'membership'
              AND p.plan_type = 'recurring'
        ), 0)::numeric AS recurring_cents,
        COALESCE(sum(li.amount) FILTER (
            WHERE li.item_type = 'membership'
              AND p.plan_type IN ('one_time', 'trial')
        ), 0)::numeric AS onetime_cents
    FROM member_invoice_line_items li
    LEFT JOIN member_memberships mm ON mm.item_id = li.item_id
    LEFT JOIN membership_plans p ON p.plan_id = mm.plan_id
    WHERE li.gym_id = CAST(:gym_id AS UUID)
    GROUP BY li.invoice_id
),
charges AS (
    SELECT
        (c.charge_time AT TIME ZONE gd.tz)::date AS charge_date,
        c.amount * CASE
            -- No recorded lines: proration-only invoice, all recurring.
            WHEN s.invoice_id IS NULL THEN 1::numeric
            ELSE COALESCE(
                s.recurring_cents / NULLIF(s.recorded_cents, 0), 0
            )
        END AS recurring_cents,
        c.amount * CASE
            -- No recorded lines is recurring, so it carries no one-time share.
            WHEN s.invoice_id IS NULL THEN 0::numeric
            ELSE COALESCE(
                s.onetime_cents / NULLIF(s.recorded_cents, 0), 0
            )
        END AS onetime_cents
    FROM member_charges c
    CROSS JOIN gym_day gd
    LEFT JOIN invoice_split s ON s.invoice_id = c.invoice_id
    WHERE c.gym_id = CAST(:gym_id AS UUID)
      AND c.status = 'succeeded'
),
bounds AS (
    SELECT
        gd.today,
        COALESCE(
            (SELECT min(ch.charge_date) FROM charges ch),
            gd.today
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
        round(COALESCE(sum(ch.recurring_cents), 0))::bigint AS recurring,
        round(COALESCE(sum(ch.onetime_cents), 0))::bigint AS onetime
    FROM months mo
    LEFT JOIN charges ch
        ON ch.charge_date >= mo.month_start
       AND ch.charge_date < mo.next_month_start
    GROUP BY mo.month_start
)
SELECT jsonb_build_object(
    'unit', 'cents',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'recurring',
            'label', 'Recurring',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.recurring
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'onetime',
            'label', 'One-time',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.onetime
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
