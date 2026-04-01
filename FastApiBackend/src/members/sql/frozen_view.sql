SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    m.freeze_start_date,
    m.freeze_end_date,
    m.total_price,
    mp.duration_unit
FROM user_gym_profiles p
JOIN member_memberships m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
ORDER BY
    (CURRENT_DATE - m.freeze_start_date) ASC
LIMIT :limit OFFSET :offset
