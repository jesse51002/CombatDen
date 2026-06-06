-- DB-first cancel: set cancel_date (the membership stays active through its paid
-- period). Status stays 'applied' — the cancel_date-immutable trigger only locks
-- cancel_date once the membership is actually removed from Stripe ('deleted'), so
-- a sync that does not confirm can revert by clearing cancel_date (no status to
-- stage/un-stage). The writeback stamps 'deleted' on success. stripe_item_id is
-- left intact (historical invoice-line record).
UPDATE member_memberships_unfiltered mm
SET
    cancel_date = GREATEST(COALESCE(mm.next_due_date, :gym_today), :gym_today)
WHERE mm.item_id   = :item_id
  AND mm.member_id = :member_id
RETURNING cancel_date
