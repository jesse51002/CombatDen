SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.email,
    p.phone,
    m.next_due_date,
    m.total_price,
    m.end_date,
    m.freeze_end_date,
    m.status,
    mp.plan_type,
    mp.plan_name,
    mp.duration_unit
FROM user_gym_profiles p
JOIN member_memberships m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
{where_clause}
    AND m.next_due_date < CURRENT_DATE
ORDER BY
    (CURRENT_DATE - m.next_due_date) DESC
LIMIT :limit OFFSET :offset
