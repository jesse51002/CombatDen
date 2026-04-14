SELECT item_id,
       crm_user_id,
       gym_id
FROM member_memberships
WHERE stripe_item_id = :stripe_item_id
  AND gym_id = :gym_id
LIMIT 1
