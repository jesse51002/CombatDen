UPDATE user_gym_profiles
SET stripe_sub_id_month = :stripe_sub_id_month
WHERE crm_user_id = :crm_user_id
