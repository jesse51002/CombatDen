DELETE FROM membership_plans_unfiltered
WHERE plan_id = :plan_id AND gym_id = :gym_id AND stripe_product_id IS NULL
