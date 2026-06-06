-- REVERT (service-role): clear cancel_date to undo a DB-first cancel whose sync
-- did not confirm on Stripe. Restores the membership to active so the DB stays in
-- sync with Stripe (which still carries the line). Only touches cancel_date — the
-- stripe_item_id is left intact (historical invoice-line record). Idempotent.
UPDATE member_memberships_unfiltered
SET cancel_date = NULL
WHERE item_id   = :item_id
  AND member_id = :member_id
