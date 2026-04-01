SELECT
    COUNT(*) FILTER (
        WHERE m.status = 'active'
        AND mp.plan_type != 'trial'
    ) AS active,
    COUNT(*) FILTER (
        WHERE mp.plan_type = 'trial'
        AND m.status = 'active'
    ) AS trial,
    COUNT(*) FILTER (
        WHERE m.status = 'frozen'
    ) AS frozen,
    COUNT(*) FILTER (
        WHERE m.next_due_date < CURRENT_DATE
    ) AS overdue
FROM member_memberships m
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
WHERE m.gym_id = :gym_id
