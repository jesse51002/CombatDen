UPDATE user_gym_profiles_unfiltered
SET freeze_start_date = CURRENT_DATE,
    freeze_end_date   = :freeze_end_date
WHERE crm_user_id = :crm_user_id
  AND gym_id      = :gym_id
