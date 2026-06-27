-- Preview self-heal: restore any leaked preview_remove applied-discount rows
-- for the payer back to 'applied'. A preview_remove applied-discount row means
-- a prior remove-discount preview crashed between staging (flip to preview_remove)
-- and cleanup (flip back to applied), leaving the real row hidden. Restoring it
-- to 'applied' makes it visible again and repairs the billing state.
-- Scoped via the payer: the applied-discount's membership must belong to the
-- payer (paid_by_member_id). Run BEFORE the membership restore
-- (member_memberships_sweep_preview_restore.sql) so applied-discount restores
-- happen in a consistent state.
UPDATE member_membership_applied_discounts_unfiltered
SET stripe_sync_status = 'applied'
WHERE stripe_sync_status = 'preview_remove'
  AND item_id IN (
      SELECT item_id
      FROM member_memberships_unfiltered
      WHERE paid_by_member_id = :payer_member_id
  )
RETURNING applied_discount_id
