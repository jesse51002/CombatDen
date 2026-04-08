SELECT
    crm_user_id,
    gym_id,
    first_name,
    last_name,
    phone,
    email,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    account_linked_to_id,
    stripe_customer_id,
    stripe_payment_method_id,
    card_brand,
    card_last_four,
    card_exp_month,
    card_exp_year
FROM user_gym_profiles
WHERE crm_user_id = :crm_user_id
