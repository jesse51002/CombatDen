-- Collected by Method (bars, cents, monthly, all-time).
--
-- Three series over the gym-local months from the gym's first succeeded charge
-- through the current month: card, cash and other. Only succeeded charges
-- count, and because refunds are stored as NEGATIVE amounts a plain SUM is
-- already "collected minus refunds" - the same net rule revenue_hero uses for
-- its collected segment.
--
-- THE BUCKETS ARE EXHAUSTIVE, and that is the point: anything that is not
-- payment_method_type 'card' or 'cash' - a bank debit, a wallet, a NULL on an
-- older row - falls into 'other'. So card + cash + other always equals total
-- collected for that month, and a new Stripe payment method type can never
-- silently vanish from the chart.
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
        CASE
            WHEN c.payment_method_type = 'card' THEN 'card'
            WHEN c.payment_method_type = 'cash' THEN 'cash'
            ELSE 'other'
        END AS method,
        c.amount
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
        COALESCE(
            sum(ch.amount) FILTER (WHERE ch.method = 'card'), 0
        )::bigint AS card,
        COALESCE(
            sum(ch.amount) FILTER (WHERE ch.method = 'cash'), 0
        )::bigint AS cash,
        COALESCE(
            sum(ch.amount) FILTER (WHERE ch.method = 'other'), 0
        )::bigint AS other
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
            'key', 'card',
            'label', 'Card',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.card
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'cash',
            'label', 'Cash',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.cash
                        )
                        ORDER BY p.month_start
                    )
                    FROM points p
                ),
                '[]'::jsonb
            )
        ),
        jsonb_build_object(
            'key', 'other',
            'label', 'Other',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.other
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
