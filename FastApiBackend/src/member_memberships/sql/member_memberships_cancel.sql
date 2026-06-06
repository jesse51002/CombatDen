-- DB-first cancel: set cancel_date (the membership stays active through its paid
-- period) and stage stripe_sync_status = 'migrating'. The 'migrating' state lets a
-- sync that does not confirm REVERT the cancel — the cancel_date-immutable trigger
-- permits clearing cancel_date only while the row is 'migrating'. The writeback
-- stamps 'deleted' on success. stripe_item_id is left intact (historical
-- invoice-line record).
UPDATE member_memberships_unfiltered mm
SET
    cancel_date        = GREATEST(COALESCE(mm.next_due_date, :gym_today), :gym_today),
    stripe_sync_status = 'migrating'
WHERE mm.item_id   = :item_id
  AND mm.member_id = :member_id
RETURNING cancel_date
