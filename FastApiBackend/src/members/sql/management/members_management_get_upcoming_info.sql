-- Return the data needed to fetch a member's OWN upcoming (next) Stripe
-- invoice: the member's monthly subscription id and the gym's Connect
-- account id. Under per-payer billing each payer funds their own
-- subscription, so this reads the queried member's OWN stripe_sub_id_month
-- (NO parent resolution) — callers pass the PAYER whose invoice they want.
-- A member with no own subscription (their memberships are paid by someone
-- else) has a null stripe_sub_id_month and yields no upcoming invoice.
SELECT
    mbp.stripe_sub_id_month,
    g.stripe_account_id,
    mbp.gym_id
FROM member_billing_profile mbp
JOIN gyms g ON g.gym_id = mbp.gym_id
WHERE mbp.member_id = :member_id
