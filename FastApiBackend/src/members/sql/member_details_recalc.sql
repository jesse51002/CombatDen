SELECT
    m.crm_user_id,
    m.gym_id,
    m.plan_id,
    m.status,
    m.discount_ids,
    m.total_price,
    mp.plan_name,
    mp.plan_type,
    mp.base_cost,
    mp.additional_member_discount,
    p.account_linked_to_id
FROM member_memberships_status m
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN user_gym_profiles p
    ON m.crm_user_id = p.crm_user_id
    AND m.gym_id = p.gym_id
WHERE m.gym_id = :gym_id
  AND m.crm_user_id = ANY(:family_ids)
  AND m.status IN ('active', 'frozen')
