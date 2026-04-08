SELECT mm.crm_user_id, mm.plan_id
FROM member_memberships mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.crm_user_id = ANY(:crm_user_ids)
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
