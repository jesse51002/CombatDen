DELETE FROM member_memberships_unfiltered
WHERE item_id = ANY(:item_ids) AND stripe_item_id IS NULL
