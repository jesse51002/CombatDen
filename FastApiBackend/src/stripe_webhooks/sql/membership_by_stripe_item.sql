-- Resolve a Stripe subscription-item line to its membership row: the OWNER
-- (member_id — invoice/charge attribution) and the PAYER (paid_by_member_id —
-- whose subscription billed it; the once-settle + its lock key).
SELECT item_id,
       member_id,
       paid_by_member_id,
       gym_id
FROM member_memberships
WHERE stripe_item_id = :stripe_item_id
  AND gym_id = :gym_id
LIMIT 1
