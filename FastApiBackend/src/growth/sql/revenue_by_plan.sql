-- Revenue by Plan (breakdown, cents) - the current net monthly recurring
-- run-rate split across the plans producing it.
--
-- LIVE MEMBERSHIP is the contracted set, identical to the MRR tile and to
-- mrr_trend's newest point: a recurring-plan membership that has started
-- (start_date on or before gym-local today) and is not yet terminal (LEAST of
-- cancel_date / end_date, which skips NULLs). Freeze is deliberately ignored -
-- a freeze pauses the bill, not the contract - so these values always sum to
-- the MRR tile.
--
-- Money comes from member_memberships.total_price, the POST-discount
-- per-membership price the payment sync writes back, so what a plan shows here
-- is what its members are actually billed. Discount math is never re-derived.
-- Plans with no live membership produce no row, so a gym that has never sold a
-- recurring plan yields an empty item list rather than a wall of zeros.
WITH gym_day AS (
    SELECT (now() AT TIME ZONE g.timezone)::date AS today
    FROM gyms g
    WHERE g.gym_id = CAST(:gym_id AS UUID)
)
SELECT jsonb_build_object(
    'unit', 'cents',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', CAST(t.plan_id AS TEXT),
                    'label', t.plan_name,
                    'value', t.cents
                )
                ORDER BY t.cents DESC, t.plan_name
            )
            FROM (
                SELECT
                    p.plan_id,
                    p.plan_name,
                    sum(mm.total_price)::bigint AS cents
                FROM member_memberships mm
                JOIN membership_plans p ON p.plan_id = mm.plan_id
                CROSS JOIN gym_day gd
                WHERE mm.gym_id = CAST(:gym_id AS UUID)
                  AND p.plan_type = 'recurring'
                  AND mm.start_date <= gd.today
                  AND (
                      LEAST(mm.cancel_date, mm.end_date) IS NULL
                      OR LEAST(mm.cancel_date, mm.end_date) > gd.today
                  )
                GROUP BY p.plan_id, p.plan_name
            ) t
        ),
        '[]'::jsonb
    )
) AS data
