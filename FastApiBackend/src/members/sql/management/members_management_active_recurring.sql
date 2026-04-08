SELECT mm.gym_id, mm.plan_id
FROM member_memberships mm
JOIN membership_plans mp
  ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.crm_user_id = :crm_user_id
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NULL
  AND (mm.end_date IS NULL OR mm.end_date > CURRENT_DATE)
