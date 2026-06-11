-- Remove a discount from a membership: DELETE its frozen snapshot row. Scoped
-- by member_id as a tenant guard so a caller can only delete a snapshot on a
-- membership they own.
DELETE FROM member_membership_applied_discounts_unfiltered
WHERE applied_discount_id = :applied_discount_id
  AND member_id = :member_id
