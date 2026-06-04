-- Delete a pending member shell whose Stripe customer never materialised.
-- The stripe_customer_id IS NULL guard makes it impossible to delete a member
-- that already has a customer, so this can only ever remove a freshly inserted
-- row when the Stripe customer create failed during member creation.
DELETE FROM members
WHERE member_id = :member_id
  AND stripe_customer_id IS NULL
