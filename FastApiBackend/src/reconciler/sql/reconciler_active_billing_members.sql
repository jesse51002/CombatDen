-- Distinct paying parents that have at least one ACTIVE recurring membership
-- somewhere in their family, restricted to parents that have a Stripe customer.
-- Serves two sweeps: the push sweep (C) takes member_id and hands it to
-- bulk_payment_sync, which re-resolves each to its family and locks it (passing
-- the resolved parent, not each child, avoids converging the same family twice);
-- the status sweep (B) takes gym_id + stripe_sub_id_month to read the live sub.
-- 'active' excludes cancelled / ended / frozen -- the states actually billing now.
-- gym_id / stripe_sub_id_month are functionally determined by the parent, so
-- DISTINCT still yields one row per paying parent.
SELECT DISTINCT
    COALESCE(m.account_linked_to_id, m.member_id) AS member_id,
    parent.gym_id,
    parent.stripe_sub_id_month
FROM member_memberships_status mms
JOIN members m
    ON m.member_id = mms.member_id
JOIN membership_plans mp
    ON mp.plan_id = mms.plan_id AND mp.gym_id = mms.gym_id
JOIN members parent
    ON parent.member_id = COALESCE(m.account_linked_to_id, m.member_id)
WHERE mms.status = 'active'
  AND mp.plan_type = 'recurring'
  AND parent.stripe_customer_id IS NOT NULL
