-- The `once` applied discounts for a family that are candidates for
-- consumption: still unconsumed (no end_date) and already carrying a coupon, so
-- the sync can check each against the live Stripe subscription. A `once` with no
-- coupon yet (never synced) is excluded — it has not been attached, so it cannot
-- be consumed. Reads the unfiltered base tables (service-role): half-synced rows
-- must still be visible to the sync that resolves them.
SELECT
    ad.applied_discount_id,
    ad.stripe_coupon_id
FROM member_membership_applied_discounts_unfiltered ad
JOIN gym_discount_values_unfiltered v
    ON ad.value_id = v.value_id
WHERE ad.member_id = ANY(:member_ids)
  AND v.discount_mode = 'once'
  AND ad.end_date IS NULL
  AND ad.stripe_coupon_id IS NOT NULL
