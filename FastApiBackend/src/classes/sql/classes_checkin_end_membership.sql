UPDATE member_memberships
SET end_date = :end_date
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
  AND plan_id = :plan_id
