-- Stage / revert a membership's stripe_sync_status (service-role). Used by the
-- preview dry-run to stamp a row 'preview_remove' (so the preview build drops it)
-- and to restore it afterward. CAST avoids the asyncpg text-bind issue on the enum
-- column. Touches only stripe_sync_status — never cancel_date / stripe_item_id.
UPDATE member_memberships_unfiltered
SET stripe_sync_status = CAST(:sync_status AS stripe_sync_status)
WHERE item_id   = :item_id
  AND member_id = :member_id
