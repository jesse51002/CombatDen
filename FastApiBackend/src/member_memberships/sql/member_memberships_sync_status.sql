-- Read one membership's Stripe-sync status from the UNFILTERED base table
-- (service-role) so a DB-first caller can VERIFY the sync landed. A pending row
-- is 'not_added' until the writeback stamps 'applied'; a cancelled row becomes
-- 'deleted' once the sync confirms Stripe dropped its line. The client-facing
-- view hides not_added / preview / deleted rows, so the verify must read the
-- base table to see the status transition.
SELECT stripe_sync_status
FROM member_memberships_unfiltered
WHERE item_id   = :item_id
  AND member_id = :member_id
