-- Reprice-preview cleanup: hard-delete the staged rows' preview discount
-- copies. The 'preview_add' gate is a safety net — only the preview ever
-- pins discounts to a staged (preview_add) membership row.
DELETE FROM member_membership_applied_discounts_unfiltered
WHERE item_id = ANY(CAST(:item_ids AS UUID[]))
  AND stripe_sync_status = 'preview_add'
