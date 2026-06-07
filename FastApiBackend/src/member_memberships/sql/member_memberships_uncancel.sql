-- REVERT (service-role): undo a DB-first cancel whose sync did not confirm. Clears
-- cancel_date. The cancel_date-immutable trigger permits this as long as the
-- membership has not been removed from Stripe yet (stripe_sync_status <> 'deleted')
-- — i.e. the cancel never landed, which is exactly the revert case. Status is left
-- 'applied' (it was never changed); stripe_item_id is left intact.
UPDATE member_memberships_unfiltered
SET cancel_date = NULL
WHERE item_id   = :item_id
  AND member_id = :member_id
