SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.email,
    p.last_class,
    m.status,
    m.last_paid_date,
    m.next_due_date,
    m.total_price,
    m.end_date,
    m.freeze_end_date,
    m.cancel_date,
    mp.plan_type,
    mp.plan_name,
    mp.duration_unit,
    (now() AT TIME ZONE g.timezone)::date AS gym_today
FROM user_gym_profiles p
LEFT JOIN member_memberships_status m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
LEFT JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
{where_clause}
ORDER BY p.last_class is null, p.last_class DESC
