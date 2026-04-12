SELECT 1
FROM member_memberships_status
WHERE crm_user_id = :crm_user_id
  AND gym_id      = :gym_id
  AND plan_id     = :plan_id
  AND status IN ('active', 'frozen')
