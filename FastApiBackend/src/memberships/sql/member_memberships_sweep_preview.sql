-- Preview self-heal: delete any leaked preview_add membership rows for the
-- payer. Preview rows are always transient (staged, then deleted in the
-- preview's finally); any that persist are leaks from a crashed / killed
-- preview. Scoped to the payer (paid_by_member_id) so a CONCURRENT preview of
-- another payer's in-flight rows is untouched, and safe because nothing real
-- is ever preview_add. Run AFTER member_memberships_sweep_preview_discounts.sql
-- (the applied-discount FK RESTRICTs on these rows).
DELETE FROM member_memberships_unfiltered
WHERE paid_by_member_id = :payer_member_id
  AND stripe_sync_status = 'preview_add'
RETURNING item_id, member_id, plan_id, price_id, start_date, created_at
