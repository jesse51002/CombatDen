UPDATE member_memberships
SET stripe_item_id = :stripe_item_id
WHERE crm_user_id = :crm_user_id
  AND price_id = :price_id
