UPDATE user_gym_profiles_unfiltered
SET stripe_customer_id       = :stripe_customer_id,
    stripe_payment_method_id = :stripe_payment_method_id,
    card_brand               = :card_brand,
    card_last_four           = :card_last_four,
    card_exp_month           = :card_exp_month,
    card_exp_year            = :card_exp_year
WHERE crm_user_id = :crm_user_id
RETURNING *
