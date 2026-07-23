-- Revenue Billed (line, cents, monthly, all-time).
--
-- THE LINE SERIES: ALL revenue ACTUALLY BILLED in each gym-local month, read
-- from payment history - recurring + one-time + trial + cash, every succeeded
-- charge. It is NOT a contracted run-rate "as of month end": a point is money
-- that moved, not money that was owed.
--
-- Two consequences the CRM must not hide:
--   * THE NEWEST POINT IS PARTIAL. The current month is still in progress, so
--     its point counts only the charges that have landed so far and is
--     expected to sit LOW against the completed months beside it. It is not a
--     collapse in revenue.
--   * It does not equal the Recurring Revenue KPI tile. That tile is the
--     current run-rate (what the gym bills per month going forward); this line
--     is history, and it is ALL revenue, not just the recurring share.
--
-- WHY CHARGES AND NOT MEMBERSHIP DATES: a FROZEN member is not billed, so
-- their contracted price must not count as revenue. Only the CURRENT freeze
-- window is stored (members.freeze_start_date / freeze_end_date) - a freeze
-- that has already ended leaves no trace - so no membership-date reconstruction
-- could honour that rule for any month but the newest. A charge is the freeze
-- rule encoded permanently: a frozen member simply generates none.
--
-- REVENUE = NET SUCCEEDED CASH, WHOLE CHARGE, NO APPORTIONMENT. Only succeeded
-- charges count (c.status = 'succeeded'); refunds ride the same history stored
-- NEGATIVE (kind = 'refund'), so a plain SUM of member_charges.amount is
-- ALREADY net of refunds. This is the exact status + refund convention
-- revenue_hero (its "collected" segment) and revenue_collected use, so every
-- revenue metric agrees on what "revenue" means. Unlike those two there is no
-- invoice split here: the whole charge amount counts regardless of whether the
-- invoice it paid was recurring, one-time, trial or a custom cash charge.
--
-- The month grid runs from the gym's first succeeded charge through the
-- current gym-local month with zero-filled gaps - the same grid
-- revenue_collected draws, so the two charge-derived charts line up exactly.
WITH gym_day AS (
    SELECT
        g.timezone AS tz,
        (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
charges AS (
    SELECT
        (c.charge_time AT TIME ZONE gd.tz)::date AS charge_date,
        c.amount AS cents
    FROM member_charges c
    CROSS JOIN gym_day gd
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
        COALESCE(sum(ch.cents), 0)::bigint AS revenue
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
            'key', 'revenue',
            'label', 'Revenue',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.revenue
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
