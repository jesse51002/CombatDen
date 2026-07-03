SELECT
    reward_id,
    title,
    price_label,
    image_url,
    point_cost
FROM gym_rewards
WHERE gym_id = :gym_id
