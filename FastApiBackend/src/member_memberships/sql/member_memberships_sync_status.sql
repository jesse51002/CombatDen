-- Read one membership's Stripe-sync status from the UNFILTERED base table
-- (service-role) so a DB-first caller can VERIFY the sync landed. A pending add is
-- 'not_added' until the writeback stamps 'applied'; a cancel stages 'migrating'
-- then the writeback stamps 'deleted'; a price migration stages 'migrating' then
-- the writeback stamps 'applied'. The client-facing view hides not_added /
-- preview / deleted rows, so the verify must read the base table.
SELECT stripe_sync_status
FROM member_memberships_unfiltered
WHERE item_id   = :item_id
  AND member_id = :member_id
