UPDATE user_gym_profiles_unfiltered
SET linked_discount_id = :linked_discount_id
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
