SELECT
    mbp.member_id,
    mbp.gym_id,
    mbp.first_name,
    mbp.last_name,
    mbp.email,
    mbp.phone,
    mbp.stripe_customer_id,
    mbp.stripe_payment_method_id,
    g.stripe_account_id
FROM members mbp
JOIN gyms g ON g.gym_id = mbp.gym_id
WHERE mbp.member_id = :member_id
