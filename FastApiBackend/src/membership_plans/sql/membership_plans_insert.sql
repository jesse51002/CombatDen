INSERT INTO membership_plans_unfiltered (
    gym_id,
    plan_name,
    plan_type,
    class_count,
    duration_amount,
    duration_unit,
    is_public,
    stripe_product_id,
    waiver_ids,
    linked_discount_enabled,
    linked_discount_ids
) VALUES (
    :gym_id,
    :plan_name,
    :plan_type,
    :class_count,
    :duration_amount,
    :duration_unit,
    :is_public,
    :stripe_product_id,
    CAST(:waiver_ids AS JSONB),
    :linked_discount_enabled,
    CAST(:linked_discount_ids AS JSONB)
)
RETURNING *
