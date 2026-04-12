DELETE FROM membership_plan_prices_unfiltered
WHERE price_id = :price_id AND plan_id = :plan_id AND stripe_price_id IS NULL
