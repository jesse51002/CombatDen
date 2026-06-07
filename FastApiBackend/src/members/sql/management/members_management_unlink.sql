UPDATE members
SET
    account_linked_to_id = NULL
WHERE member_id = :member_id
RETURNING
    member_id,
    gym_id,
    phone,
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
