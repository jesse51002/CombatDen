UPDATE member_memberships
SET price_id       = :new_price_id,
    total_price    = :total_price
WHERE item_id     = :item_id
  AND crm_user_id = :crm_user_id
