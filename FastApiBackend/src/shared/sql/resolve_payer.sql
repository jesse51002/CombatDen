-- The PAYER's own billing profile — a direct lookup, no parent redirect.
-- Same shape as resolve_parent.sql minus the link-following self-join, so
-- both hydrate the same PayerProfile model.
SELECT
    p.member_id,
    p.gym_id,
    p.stripe_customer_id,
    p.stripe_sub_id_month,
    p.freeze_start_date,
    p.freeze_end_date,
    g.timezone
FROM member_billing_profile p
JOIN gyms g ON g.gym_id = p.gym_id
WHERE p.member_id = :payer_member_id
