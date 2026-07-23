-- Raw applied membership discounts for the gym (UNFILTERED base table -- the
-- slim snapshots pinning a membership to a discount value version).
SELECT
    amd.applied_discount_id,
    amd.item_id,
    amd.member_id,
    amd.gym_id,
    amd.value_id,
    amd.end_date,
    amd.stripe_coupon_id,
    amd.stripe_sync_status,
    amd.created_at
FROM member_membership_applied_discounts_unfiltered amd
WHERE amd.gym_id = CAST(:gym_id AS UUID)
ORDER BY amd.created_at ASC, amd.applied_discount_id ASC
