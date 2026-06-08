-- Distinct paying parents that have at least one ACTIVE recurring membership
-- somewhere in their family, restricted to parents that have a Stripe customer.
-- Feeds the push sweep: each member_id goes to bulk_payment_sync, which
-- re-resolves it to its family and locks it (passing the resolved parent, not
-- each child, avoids converging the same family twice).
-- 'active' excludes cancelled / ended / frozen -- the states actually billing now.
SELECT DISTINCT
    COALESCE(m.account_linked_to_id, m.member_id) AS member_id
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
