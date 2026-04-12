UPDATE member_memberships_unfiltered
SET stripe_item_id = :stripe_item_id
WHERE item_id     = :item_id
  AND crm_user_id = :crm_user_id
RETURNING *
