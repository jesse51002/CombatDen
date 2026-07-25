UPDATE members
SET
    stripe_customer_id       = :stripe_customer_id,
    stripe_payment_method_id = :stripe_payment_method_id,
    card_brand               = :card_brand,
    card_last_four           = :card_last_four,
    card_exp_month           = :card_exp_month,
    card_exp_year            = :card_exp_year
WHERE member_id = :member_id
RETURNING
    member_id,
    gym_id,
    phone,
    address,
    date_of_birth,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    stripe_customer_id,
    stripe_payment_method_id,
    card_brand,
    card_last_four,
    card_exp_month,
    card_exp_year
