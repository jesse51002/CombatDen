-- Resolve a Stripe subscription-item line to ALL the memberships it bills.
-- A consolidated item (quantity > 1) maps to MULTIPLE member_memberships — the
-- co-owners who share one price line (the sync merges same-price memberships
-- into one Stripe item). Returns every owner (member_id) + the shared payer
-- (paid_by_member_id is the same across them: one subscription = one payer).
-- NO LIMIT: dropping co-owners here is how a second person on a shared item
-- went missing from paid_for / payment-date updates.
SELECT item_id,
       member_id,
       paid_by_member_id,
       gym_id
FROM member_memberships
WHERE stripe_item_id = :stripe_item_id
  AND gym_id = :gym_id
