-- The PAYER's own billing profile — a direct lookup of their row, no
-- link-following, no parent redirect. The payer is whoever a membership's
-- paid_by_member_id names (or an explicit request payer).
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
