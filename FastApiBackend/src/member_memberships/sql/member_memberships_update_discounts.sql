UPDATE member_memberships_unfiltered
SET discount_ids = CAST(:discount_ids AS jsonb)
WHERE item_id   = :item_id
  AND member_id = :member_id
