SELECT crm_user_id, linked_discount_id
FROM user_gym_profiles
WHERE crm_user_id = ANY(:crm_user_ids)
  AND linked_discount_id IS NOT NULL
