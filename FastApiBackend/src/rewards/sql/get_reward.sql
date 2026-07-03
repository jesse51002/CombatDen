SELECT
    reward_id,
    gym_id,
    title,
    point_cost,
    image_url,
    price_label,
    is_active,
    created_at
FROM gym_rewards
WHERE reward_id = :reward_id
