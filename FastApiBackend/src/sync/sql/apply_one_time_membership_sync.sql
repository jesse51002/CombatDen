-- Stamp the one-time charge result onto one membership row (real path).
--
-- Writes the invoice LINE id (stripe_item_id), the consolidated invoice id
-- (stripe_one_time_invoice_id), the post-discount price paid (total_price), and
-- stripe_sync_status = 'applied' — confirming the row is billed. Both ids are
-- NULL→value on first charge (the immutable triggers allow that single
-- transition; a one-time membership is terminal, so this runs exactly once).
-- No next_due_date: a one-time membership has no recurring cycle.
UPDATE member_memberships_unfiltered
SET stripe_item_id = :stripe_item_id,
    stripe_one_time_invoice_id = :stripe_one_time_invoice_id,
    total_price = :total_price,
    stripe_sync_status = 'applied'
WHERE item_id = :item_id
  AND member_id = :member_id
