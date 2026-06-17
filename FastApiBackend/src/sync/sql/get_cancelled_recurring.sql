-- Read the PAYER's CANCELLED recurring memberships that still carry a Stripe
-- line id and are not yet marked deleted. The writeback stamps every one of
-- them 'deleted' after a successful converge: the desired state excludes all
-- cancelled rows by construction, so the converge removed each row's billing —
-- its line, or its share of a consolidated line (whose id may stay live for
-- the payer's remaining members on that price). Reads the unfiltered base
-- table (service-role).
SELECT
    mm.item_id
FROM member_memberships_unfiltered mm
JOIN membership_plans mp
    ON mm.plan_id = mp.plan_id AND mm.gym_id = mp.gym_id
WHERE mm.paid_by_member_id = :payer_member_id
  AND mp.plan_type = 'recurring'
  AND mm.cancel_date IS NOT NULL
  AND mm.stripe_item_id IS NOT NULL
  AND mm.stripe_sync_status <> 'deleted'
