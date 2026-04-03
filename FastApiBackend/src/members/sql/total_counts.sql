SELECT
    COUNT(DISTINCT m.crm_user_id) FILTER (
        WHERE m.status = 'active'
        AND mp.plan_type != 'trial'
    ) AS active,
    COUNT(DISTINCT m.crm_user_id) FILTER (
        WHERE mp.plan_type = 'trial'
        AND m.status = 'active'
    ) AS trial,
    COUNT(DISTINCT m.crm_user_id) FILTER (
        WHERE m.status = 'frozen'
    ) AS frozen,
    COUNT(DISTINCT m.crm_user_id) FILTER (
        WHERE m.next_due_date < CURRENT_DATE
    ) AS overdue
FROM member_memberships_status m
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
WHERE m.gym_id = :gym_id
