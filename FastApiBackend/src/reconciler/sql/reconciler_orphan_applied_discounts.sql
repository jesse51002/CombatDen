-- Delete the applied-discount snapshot rows that FK-reference an orphaned
-- 'not_added' membership item (fk_applied_discount_membership_gym on
-- member_membership_applied_discounts_unfiltered -> member_memberships_unfiltered).
-- Must run BEFORE the item's own delete, in the same transaction, or the FK
-- blocks the orphan cleanup (an orphan with applied-discount children could
-- otherwise never be swept). Scoped to 'not_added' -- the same "never
-- confirmed" guard the reprice-revert path uses for copied discounts
-- (applied_discounts/delete_copied_discounts.sql) -- so a synced discount is
-- never touched, and only the exact orphan's own children are removed.
DELETE FROM member_membership_applied_discounts_unfiltered
WHERE item_id = :item_id
  AND stripe_sync_status = 'not_added'
