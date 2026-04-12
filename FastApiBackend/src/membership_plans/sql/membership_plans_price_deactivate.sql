UPDATE membership_plan_prices_unfiltered
SET is_active = false
WHERE plan_id = :plan_id
  AND gym_id  = :gym_id
  AND is_active = true
  AND price_id <> :exclude_price_id
RETURNING *
