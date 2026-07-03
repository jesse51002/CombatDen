INSERT INTO gym_rewards (
    gym_id,
    title,
    point_cost,
    image_url,
    price_label
)
VALUES (
    :gym_id,
    :title,
    :point_cost,
    :image_url,
    :price_label
)
RETURNING
    reward_id,
    gym_id,
    title,
    point_cost,
    image_url,
    price_label,
    is_active,
    created_at
