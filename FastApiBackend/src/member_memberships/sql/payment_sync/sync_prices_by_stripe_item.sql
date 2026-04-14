-- Fan out the post-discount per-unit price to every row sharing a
-- stripe_item_id. Rows with stripe_item_id IS NULL are never touched
-- because `stripe_item_id = NULL` is never true.
UPDATE member_memberships_unfiltered
SET total_price = :total_price
WHERE stripe_item_id = :stripe_item_id
