-- Recurring Revenue (line, cents, monthly, all-time).
--
-- One series: the net monthly recurring run-rate as it stood at the end of
-- each gym-local month, from the month of the gym's first membership through
-- the current month. A membership counts toward a month when it had started by
-- the as-of date and was not yet terminal then (LEAST of cancel_date /
-- end_date, which skips NULLs) and its plan is recurring.
--
-- The CURRENT month's as-of date is capped at today rather than the (future)
-- month end. Without the cap, a cancellation already scheduled for later this
-- month would drop out of the newest point - the line would show a churn that
-- has not happened yet, and would disagree with the MRR tile. Capping makes
-- the last point mean "as of right now", which is exactly what the tile shows.
--
-- FREEZE IS IGNORED here, on purpose. Only the CURRENT freeze window is stored
-- on the member, so a past month's freeze state is simply not recoverable; a
-- frozen membership is a paused bill, not a cancelled contract, so it stays in
-- the run-rate. revenue_kpis' MRR tile, revenue_by_plan and the revenue
-- quality tiles apply the identical rule, so every recurring-revenue number on
-- the page is derived the same way.
--
-- Money always comes from member_memberships.total_price, the POST-discount
-- per-membership price the payment sync writes back; discount math is never
-- re-derived. total_price is a CURRENT snapshot, so history is priced at
-- today's prices - the line moves with WHO was enrolled, not with repricing.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
),
bounds AS (
    SELECT
        gd.today,
        COALESCE(
            (
                SELECT min(mm.start_date)
                FROM member_memberships mm
                WHERE mm.gym_id = CAST(:gym_id AS UUID)
            ),
            gd.today
        ) AS series_start
    FROM gym_day gd
),
months AS (
    SELECT
        gs.month_ts::date AS month_start,
        LEAST(
            (gs.month_ts + INTERVAL '1 month' - INTERVAL '1 day')::date,
            b.today
        ) AS as_of
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
        (
            SELECT COALESCE(sum(mm.total_price), 0)
            FROM member_memberships mm
            JOIN membership_plans p ON p.plan_id = mm.plan_id
            WHERE mm.gym_id = CAST(:gym_id AS UUID)
              AND p.plan_type = 'recurring'
              AND mm.start_date <= mo.as_of
              AND (
                  LEAST(mm.cancel_date, mm.end_date) IS NULL
                  OR LEAST(mm.cancel_date, mm.end_date) > mo.as_of
              )
        )::bigint AS value
    FROM months mo
)
SELECT jsonb_build_object(
    'unit', 'cents',
    'granularity', 'month',
    'series', jsonb_build_array(
        jsonb_build_object(
            'key', 'mrr',
            'label', 'Recurring Revenue',
            'points', COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'date', to_char(p.month_start, 'YYYY-MM-DD'),
                            'value', p.value
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
