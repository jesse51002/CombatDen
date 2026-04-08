SELECT crm_user_id
FROM user_gym_profiles
WHERE stripe_customer_id = :stripe_customer_id
LIMIT 1
