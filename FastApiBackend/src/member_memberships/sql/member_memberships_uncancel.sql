-- REVERT (service-role): undo a DB-first cancel whose sync did not confirm. Clears
-- cancel_date and restores stripe_sync_status = 'applied'. The cancel_date-immutable
-- trigger permits clearing cancel_date only while the row is 'migrating' (staged by
-- the cancel), so this must run before any terminal status is stamped.
-- stripe_item_id is left intact (historical invoice-line record).
UPDATE member_memberships_unfiltered
SET cancel_date        = NULL,
    stripe_sync_status = 'applied'
WHERE item_id   = :item_id
  AND member_id = :member_id
