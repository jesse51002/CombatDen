SELECT
    reward_id,
    gym_id,
    title,
    point_cost,
    amount_off,
    image_url,
    is_active,
    created_at
FROM gym_rewards
WHERE reward_id = :reward_id
