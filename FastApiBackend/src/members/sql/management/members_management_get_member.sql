SELECT
    mbp.member_id,
    mbp.gym_id,
    mbp.first_name,
    mbp.last_name,
    mbp.phone,
    mbp.email,
    mbp.address,
    mbp.emergency_contact_name,
    mbp.emergency_contact_phone,
    mbp.emergency_contact_email,
    mbp.stripe_customer_id,
    mbp.stripe_payment_method_id,
    mbp.card_brand,
    mbp.card_last_four,
    mbp.card_exp_month,
    mbp.card_exp_year
FROM members mbp
WHERE mbp.member_id = :member_id
