-- Revenue by Plan (breakdown, cents) - the current net monthly recurring
-- run-rate split across the plans producing it.
--
-- ONE RULE FOR "WHO IS CURRENTLY PAYING US", identical to revenue_hero, the
-- MRR tile and ARPM: a recurring-plan membership that has STARTED (start_date
-- on or before gym-local today) and whose derived status on
-- member_memberships_status is 'active' - which drops cancelled, ended AND
-- FROZEN rows. A frozen membership is not billed (the sync prices it as a
-- 100%-off subscription), so it contributes nothing here. Nobody re-splits
-- this rule: these values always sum to the MRR tile.
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
                    sum(mms.total_price)::bigint AS cents
                FROM member_memberships_status mms
                JOIN membership_plans p ON p.plan_id = mms.plan_id
                CROSS JOIN gym_day gd
                WHERE mms.gym_id = CAST(:gym_id AS UUID)
                  AND p.plan_type = 'recurring'
                  AND mms.status = 'active'
                  AND mms.start_date <= gd.today
                GROUP BY p.plan_id, p.plan_name
            ) t
        ),
        '[]'::jsonb
    )
) AS data
