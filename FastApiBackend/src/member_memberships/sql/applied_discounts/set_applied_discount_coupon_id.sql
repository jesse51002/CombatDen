-- SYSTEM writeback (service-role): stamp the coupon the sync resolved onto an
-- applied discount. For a `once` discount this coupon is the consumption-tracking
-- handle (present on the subscription = pending, absent = consumed). Writes the
-- unfiltered base table and stamps stripe_sync_status = 'applied', which is what
-- makes the row visible to clients — the filtered view hides 'not_added' /
-- 'preview_*' rows (it gates on stripe_sync_status, not on stripe_coupon_id).
UPDATE member_membership_applied_discounts_unfiltered
SET stripe_coupon_id = :stripe_coupon_id,
    stripe_sync_status = 'applied'
WHERE applied_discount_id = :applied_discount_id
