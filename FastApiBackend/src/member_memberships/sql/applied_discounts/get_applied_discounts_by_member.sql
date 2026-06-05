-- Read every applied-discount snapshot for a family's memberships, joined to its
-- value version (for the percent/dollar + mode) and the membership's plan (so
-- the sync can group snapshots per consolidated line). Reads the unfiltered base
-- tables (service-role): half-synced rows (no stripe_coupon_id yet) must still
-- be seen by the sync that resolves them.
SELECT
    ad.applied_discount_id,
    ad.item_id,
    ad.member_id,
    ad.gym_id,
    ad.value_id,
    v.percentage_off,
    v.dollar_off,
    v.discount_mode,
    ad.end_date,
    ad.stripe_coupon_id,
    mm.plan_id,
    mm.stripe_item_id
FROM member_membership_applied_discounts_unfiltered ad
JOIN gym_discount_values_unfiltered v
    ON ad.value_id = v.value_id
JOIN member_memberships mm
    ON ad.item_id = mm.item_id AND ad.gym_id = mm.gym_id
WHERE ad.member_id = ANY(:member_ids)
