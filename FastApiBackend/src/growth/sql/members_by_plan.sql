-- Members by Plan (breakdown, count).
--
-- The active member count per plan, mirroring the enrolled-count guard in
-- plans/sql/membership_plans_active_member_count.sql: "active" is
-- member_memberships_status.status = 'active', counted DISTINCT by member so a
-- member holding two memberships on one plan counts once.
SELECT jsonb_build_object(
    'unit', 'count',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', CAST(t.plan_id AS TEXT),
                    'label', t.plan_name,
                    'value', t.member_count
                )
                ORDER BY t.member_count DESC, t.plan_name
            )
            FROM (
                SELECT
                    p.plan_id,
                    p.plan_name,
                    count(DISTINCT mms.member_id)::bigint AS member_count
                FROM member_memberships_status mms
                JOIN membership_plans p ON p.plan_id = mms.plan_id
                WHERE mms.gym_id = CAST(:gym_id AS UUID)
                  AND mms.status = 'active'
                GROUP BY p.plan_id, p.plan_name
            ) t
        ),
        '[]'::jsonb
    )
) AS data
