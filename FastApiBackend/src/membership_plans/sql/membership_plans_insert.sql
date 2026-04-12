INSERT INTO membership_plans (
    gym_id,
    plan_name,
    plan_type,
    class_count,
    duration_amount,
    duration_unit,
    is_public,
    stripe_product_id
) VALUES (
    :gym_id,
    :plan_name,
    :plan_type,
    :class_count,
    :duration_amount,
    :duration_unit,
    :is_public,
    :stripe_product_id
)
RETURNING *
