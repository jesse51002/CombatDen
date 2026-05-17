INSERT INTO gym_rewards (
    gym_id,
    title,
    point_cost,
    amount_off,
    image_url
)
VALUES (
    :gym_id,
    :title,
    :point_cost,
    :amount_off,
    :image_url
)
RETURNING
    reward_id,
    gym_id,
    title,
    point_cost,
    amount_off,
    image_url,
    is_active,
    created_at
