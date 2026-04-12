UPDATE user_gym_profiles
SET freeze_start_date = NULL,
    freeze_end_date   = NULL
WHERE crm_user_id = :crm_user_id
  AND gym_id      = :gym_id
