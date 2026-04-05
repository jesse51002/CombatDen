UPDATE member_memberships
SET end_date = CURRENT_DATE
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
  AND plan_id = :plan_id
