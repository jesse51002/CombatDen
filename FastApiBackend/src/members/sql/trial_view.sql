SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    m.start_date,
    m.end_date
FROM user_gym_profiles p
JOIN member_memberships m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
    AND mp.plan_type = 'trial'
ORDER BY (m.end_date - CURRENT_DATE) DESC
LIMIT :limit OFFSET :offset
