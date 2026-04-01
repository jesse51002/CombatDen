SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.email,
    p.current_rank,
    p.last_class,
    m.status,
    m.last_paid_date,
    m.next_due_date,
    m.total_price,
    m.end_date,
    m.freeze_end_date,
    mp.plan_type,
    mp.plan_name,
    mp.duration_unit,
    g.rank_1_name, g.rank_2_name, g.rank_3_name,
    g.rank_4_name, g.rank_5_name
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
    CASE
        WHEN mp.plan_type = 'trial'
            AND m.status = 'active' THEN 1
        WHEN m.status = 'active' THEN 2
        WHEN m.status = 'frozen' THEN 3
        WHEN m.status = 'cancelled' THEN 4
        ELSE 5
    END,
    p.created_at ASC
LIMIT :limit OFFSET :offset
