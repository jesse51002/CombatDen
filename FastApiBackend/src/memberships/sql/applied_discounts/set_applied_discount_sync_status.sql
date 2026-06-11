-- Stamp an applied-discount row's Stripe-sync status (service-role, unfiltered
-- base). Used by the discount-preview staging: flip a to-be-removed applied
-- discount to `preview_remove` (so the preview build drops it) and back to
-- `applied` on cleanup. Scoped by member_id as a tenant guard.
UPDATE member_membership_applied_discounts_unfiltered
SET stripe_sync_status = CAST(:sync_status AS stripe_sync_status)
WHERE applied_discount_id = :applied_discount_id
  AND member_id = :member_id
