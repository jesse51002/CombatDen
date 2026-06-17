-- The `once` applied discounts on a PAYER's memberships that are candidates for
-- consumption: still unconsumed (no end_date) and already carrying a coupon, so
-- the sync can check each against the payer's live Stripe subscription. A `once`
-- with no coupon yet (never synced) is excluded — it has not been attached, so it
-- cannot be consumed. Scoped by the membership's paid_by_member_id: the coupon
-- lives on the PAYER's subscription, so the candidate set must match the sub the
-- settle reads. Reads the unfiltered base tables (service-role): half-synced rows
-- must still be visible to the sync that resolves them.
SELECT
    ad.applied_discount_id,
    ad.stripe_coupon_id
FROM member_membership_applied_discounts_unfiltered ad
JOIN gym_discount_values_unfiltered v
    ON ad.value_id = v.value_id
JOIN member_memberships_unfiltered mm
    ON ad.item_id = mm.item_id AND ad.gym_id = mm.gym_id
WHERE mm.paid_by_member_id = :payer_member_id
  AND v.discount_mode = 'once'
  AND ad.end_date IS NULL
  AND ad.stripe_coupon_id IS NOT NULL
