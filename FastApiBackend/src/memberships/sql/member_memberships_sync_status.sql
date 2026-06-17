-- Read one membership's Stripe-sync status from the UNFILTERED base table
-- (service-role) so a DB-first caller can VERIFY the sync landed. A pending add is
-- 'not_added' until the writeback stamps 'applied'; a cancel keeps 'applied' (it
-- only sets cancel_date) until the writeback stamps 'deleted'. The reprice
-- executor verifies BOTH ends: its successor row 'applied' and the old row
-- 'deleted'. The verify must read the unfiltered base because the client-facing
-- view hides 'not_added' / 'preview_*' rows (it does show 'applied' / 'deleted').
SELECT stripe_sync_status
FROM member_memberships_unfiltered
WHERE item_id   = :item_id
  AND member_id = :member_id
