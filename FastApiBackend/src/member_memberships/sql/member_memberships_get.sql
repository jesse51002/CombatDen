SELECT mp.plan_type, mm.next_due_date, mm.cancel_date, mm.end_date
FROM member_memberships mm
JOIN membership_plans mp
  ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.crm_user_id = :crm_user_id
  AND mm.gym_id      = :gym_id
  AND mm.plan_id     = :plan_id
