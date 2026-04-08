SELECT
    p.crm_user_id,
    p.gym_id,
    p.first_name,
    p.last_name,
    p.email,
    p.phone,
    p.stripe_customer_id,
    p.stripe_payment_method_id,
    g.stripe_account_id
FROM user_gym_profiles p
JOIN gyms g ON p.gym_id = g.gym_id
WHERE p.crm_user_id = :crm_user_id
