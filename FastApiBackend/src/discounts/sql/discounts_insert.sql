INSERT INTO gym_discounts_unfiltered (
    gym_id,
    discount_name,
    discount_type,
    percentage_off,
    dollar_off,
    membership_plan_id,
    linked_discount_num,
    duration,
    duration_in_months,
    is_deleted,
    stripe_coupon_id
) VALUES (
    :gym_id,
    :discount_name,
    :discount_type,
    :percentage_off,
    :dollar_off,
    :membership_plan_id,
    :linked_discount_num,
    :duration,
    :duration_in_months,
    false,
    :stripe_coupon_id
)
RETURNING *
