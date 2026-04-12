UPDATE member_memberships_unfiltered
SET total_price = :total_price
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
  AND plan_id = :plan_id
