-- Insert a discount IDENTITY row (name + type). The percent/dollar + lifetime
-- live on gym_discount_values; the create service inserts the first active
-- version right after this, in the same transaction.
INSERT INTO gym_discounts_unfiltered (
    gym_id,
    discount_name,
    discount_type,
    is_deleted
) VALUES (
    :gym_id,
    :discount_name,
    :discount_type,
    false
)
RETURNING discount_id, gym_id, discount_name, discount_type, is_deleted, created_at
