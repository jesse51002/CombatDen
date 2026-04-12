INSERT INTO membership_plan_prices_unfiltered (
    plan_id,
    gym_id,
    stripe_price_id,
    price,
    is_active
) VALUES (
    :plan_id,
    :gym_id,
    :stripe_price_id,
    :price,
    true
)
RETURNING *
