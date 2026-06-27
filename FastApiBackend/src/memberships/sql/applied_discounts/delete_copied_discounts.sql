-- Reprice REVERT: remove the successor's copied applications before the
-- pending successor row itself (its FK RESTRICTs the membership delete).
-- Only unsynced copies can exist on a reverted successor — the writeback
-- stamps the membership row before it touches coupons, and the revert only
-- runs when the successor was never stamped — so the 'not_added' gate is a
-- safety net: anything else left behind makes the membership delete fail
-- loudly instead of silently dropping a synced record.
DELETE FROM member_membership_applied_discounts_unfiltered
WHERE item_id = :item_id
  AND stripe_sync_status = 'not_added'
