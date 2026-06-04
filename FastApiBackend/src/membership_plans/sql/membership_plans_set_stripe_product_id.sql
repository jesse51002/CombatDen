UPDATE membership_plans_unfiltered
SET stripe_product_id = :stripe_product_id
WHERE plan_id = :plan_id AND gym_id = :gym_id
RETURNING *
