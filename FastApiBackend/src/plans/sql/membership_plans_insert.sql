INSERT INTO membership_plans_unfiltered (
    gym_id,
    plan_name,
    image_url,
    plan_type,
    class_count,
    duration_amount,
    duration_unit,
    is_public,
    stripe_product_id,
    waiver_ids
) VALUES (
    :gym_id,
    :plan_name,
    :image_url,
    :plan_type,
    :class_count,
    :duration_amount,
    :duration_unit,
    :is_public,
    :stripe_product_id,
    CAST(:waiver_ids AS JSONB)
)
RETURNING *
