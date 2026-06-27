-- Serialize concurrent set_price on the same plan. A second caller blocks on
-- this row lock until the first commits, so two callers never both create a
-- Stripe price (the loser would strand its price when the <=1-active-price
-- index rejects its commit). Locks the base table, not the membership_plans
-- view, so FOR UPDATE is unambiguous and matches the deactivate/insert writes.
SELECT plan_id
FROM membership_plans_unfiltered
WHERE plan_id = :plan_id
  AND gym_id = :gym_id
FOR UPDATE
