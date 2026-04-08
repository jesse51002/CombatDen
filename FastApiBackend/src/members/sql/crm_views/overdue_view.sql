SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.email,
    p.phone,
    MIN(m.next_due_date) AS next_due_date,
    ARRAY_AGG(mp.plan_name) AS plan_names,
    ARRAY_AGG(m.total_price) AS prices,
    ARRAY_AGG(mp.duration_unit) AS duration_units
FROM user_gym_profiles p
JOIN member_memberships_status m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
{where_clause}
    AND m.next_due_date < CURRENT_DATE
GROUP BY p.crm_user_id
ORDER BY
    (CURRENT_DATE - MIN(m.next_due_date)) ASC
LIMIT :limit OFFSET :offset
