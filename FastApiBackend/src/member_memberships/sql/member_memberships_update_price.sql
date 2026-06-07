-- DB-first price migration: write the new price + stage stripe_sync_status. A
-- migration stages 'migrating' so the writeback may move the (otherwise immutable)
-- stripe_item_id to the new price's line; a revert restores 'applied'. CAST avoids
-- the asyncpg text-bind issue on the enum column.
UPDATE member_memberships_unfiltered
SET price_id           = :new_price_id,
    total_price        = :total_price,
    stripe_sync_status = CAST(:sync_status AS stripe_sync_status)
WHERE item_id   = :item_id
  AND member_id = :member_id
