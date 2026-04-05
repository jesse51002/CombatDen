UPDATE user_gym_profiles
SET last_class = NOW()
WHERE crm_user_id = :crm_user_id
  AND gym_id = :gym_id
