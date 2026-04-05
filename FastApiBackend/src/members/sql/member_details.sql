WITH target_profile AS (
    SELECT crm_user_id, gym_id, account_linked_to_id
    FROM user_gym_profiles
    WHERE crm_user_id = :crm_user_id
),
primary_id AS (
    SELECT COALESCE(t.account_linked_to_id, t.crm_user_id) AS id
    FROM target_profile t
),
family_group AS (
    SELECT p.crm_user_id
    FROM user_gym_profiles p
    JOIN target_profile t ON p.gym_id = t.gym_id
    CROSS JOIN primary_id pi
    WHERE p.crm_user_id = pi.id
       OR p.account_linked_to_id = pi.id
)
SELECT
    p.crm_user_id,
    p.gym_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.phone,
    p.email,
    p.address,
    p.emergency_contact_name,
    p.emergency_contact_phone,
    p.emergency_contact_email,
    p.last_class,
    p.points_balance,
    p.account_linked_to_id,
    m.plan_id,
    m.discount_ids,
    m.status       AS membership_status,
    m.start_date   AS membership_start_date,
    m.end_date     AS membership_end_date,
    m.freeze_start_date,
    m.freeze_end_date,
    m.last_paid_date,
    m.next_due_date,
    m.total_price,
    mp.plan_name,
    mp.plan_type,
    mp.base_cost,
    mp.duration_amount,
    mp.duration_unit,
    mp.additional_member_discount
FROM user_gym_profiles p
LEFT JOIN member_memberships_status m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
LEFT JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
WHERE p.crm_user_id IN (SELECT crm_user_id FROM family_group)
ORDER BY
    p.crm_user_id = :crm_user_id DESC,
    CASE m.status 
        WHEN 'active' THEN 1
        WHEN 'frozen' THEN 2
        WHEN 'ended' THEN 3 
        WHEN 'cancelled' THEN 4
    END ASC,
    CASE mp.plan_type
        WHEN 'recurring' THEN 1
        WHEN 'one_time' THEN 2
        WHEN 'trial' THEN 3
    END ASC
