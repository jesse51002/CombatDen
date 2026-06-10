DELETE FROM member_memberships_unfiltered
WHERE item_id = :item_id AND stripe_item_id IS NULL
