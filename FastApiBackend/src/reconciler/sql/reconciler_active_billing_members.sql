-- Distinct PAYERS with at least one ACTIVE recurring membership they bill,
-- restricted to payers that have a Stripe customer. Feeds the push sweep:
-- each payer goes to bulk_payment_sync, which locks the payer and converges
-- that payer's own subscription (one sync = one payer; no family resolution).
-- 'active' excludes cancelled / ended / frozen -- the states actually billing now.
SELECT DISTINCT
    mms.paid_by_member_id AS member_id
FROM member_memberships_status mms
JOIN membership_plans mp
    ON mp.plan_id = mms.plan_id AND mp.gym_id = mms.gym_id
JOIN members payer
    ON payer.member_id = mms.paid_by_member_id
WHERE mms.status = 'active'
  AND mp.plan_type = 'recurring'
  AND payer.stripe_customer_id IS NOT NULL
