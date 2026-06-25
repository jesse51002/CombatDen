-- Read the ACTIVE applied discounts for a PAYER's memberships (every row whose
-- membership is paid by :payer_member_id), joined to its value version (for the
-- percent/dollar) and the membership's plan (so the sync can group discounts per
-- consolidated line). Reads the unfiltered base tables (service-role):
-- half-synced rows (no stripe_coupon_id yet) must still be seen by the sync that
-- resolves them.
--
-- Date-lifetime filter (:today is the gym-timezone "today"): a discount is active
-- only while end_date IS NULL (forever / no cutoff) or end_date > today. This is
-- how the engine enforces a lifetime Stripe's `forever` coupons can't express:
-- a duration-bounded discount (e.g. a 1-cycle one, the single-invoice replacement
-- for the old `once` mode) drops out by the inclusive cutoff (end_date <= today
-- => expired).
SELECT
    ad.applied_discount_id,
    ad.item_id,
    ad.member_id,
    ad.gym_id,
    ad.value_id,
    v.percentage_off,
    v.dollar_off,
    ad.end_date,
    ad.stripe_coupon_id,
    mm.plan_id,
    mm.stripe_item_id
FROM member_membership_applied_discounts_unfiltered ad
JOIN gym_discount_values_unfiltered v
    ON ad.value_id = v.value_id
JOIN member_memberships_unfiltered mm
    ON ad.item_id = mm.item_id AND ad.gym_id = mm.gym_id
WHERE mm.paid_by_member_id = :payer_member_id
  AND (ad.end_date IS NULL OR ad.end_date > :today)
  AND ad.stripe_sync_status::text <> ALL(:excluded_statuses)
