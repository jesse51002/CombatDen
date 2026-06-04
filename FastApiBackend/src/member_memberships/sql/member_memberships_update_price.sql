UPDATE member_memberships_unfiltered
SET price_id    = :new_price_id,
    total_price = :total_price
WHERE item_id   = :item_id
  AND member_id = :member_id
