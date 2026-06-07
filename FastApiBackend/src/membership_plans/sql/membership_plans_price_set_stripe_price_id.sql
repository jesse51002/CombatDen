UPDATE membership_plan_prices_unfiltered
SET stripe_price_id = :stripe_price_id
WHERE price_id = :price_id AND plan_id = :plan_id
RETURNING *
