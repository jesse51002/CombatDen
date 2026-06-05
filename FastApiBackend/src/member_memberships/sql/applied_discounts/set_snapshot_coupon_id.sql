-- SYSTEM writeback (service-role): stamp the coupon the sync resolved onto a
-- snapshot. For a `once` snapshot this coupon is the consumption-tracking
-- handle (present on the subscription = pending, absent = consumed). Writes the
-- unfiltered base table so a still-pending coupon is recorded before the view
-- (stripe_coupon_id IS NOT NULL) starts exposing the row to clients.
UPDATE member_membership_applied_discounts_unfiltered
SET stripe_coupon_id = :stripe_coupon_id
WHERE applied_discount_id = :applied_discount_id
