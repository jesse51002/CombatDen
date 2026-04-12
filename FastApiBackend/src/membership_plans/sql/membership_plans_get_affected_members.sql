SELECT DISTINCT mm.crm_user_id
FROM member_memberships mm
WHERE mm.plan_id = :plan_id
  AND (mm.cancel_date IS NULL OR mm.cancel_date > CURRENT_DATE)
  AND (mm.end_date IS NULL OR mm.end_date > CURRENT_DATE)
