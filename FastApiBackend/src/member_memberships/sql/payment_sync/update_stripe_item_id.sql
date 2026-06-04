UPDATE member_memberships_unfiltered
SET stripe_item_id = :stripe_item_id
WHERE item_id   = :item_id
  AND member_id = :member_id
RETURNING *
