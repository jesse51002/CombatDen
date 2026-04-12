DELETE FROM user_gym_profiles_unfiltered
WHERE crm_user_id = :crm_user_id AND stripe_customer_id IS NULL
