-- Preview self-heal: restore any leaked preview_remove membership rows for the
-- payer back to 'applied'. A preview_remove membership row means a prior
-- cancel-preview crashed between staging (flip to preview_remove) and cleanup
-- (flip back to applied), leaving the real membership hidden from billing reads.
-- Restoring it to 'applied' makes it visible again and repairs the billing state.
-- Scoped to the payer (paid_by_member_id). Run AFTER the applied-discount
-- restore (member_memberships_sweep_preview_restore_discounts.sql) and BEFORE
-- the preview_add deletes.
UPDATE member_memberships_unfiltered
SET stripe_sync_status = 'applied'
WHERE paid_by_member_id = :payer_member_id
  AND stripe_sync_status = 'preview_remove'
RETURNING item_id, member_id, plan_id, price_id, start_date, created_at
