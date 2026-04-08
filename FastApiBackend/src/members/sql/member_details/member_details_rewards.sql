SELECT
    reward_id,
    title,
    amount_off,
    image_url,
    point_cost
FROM gym_rewards
WHERE gym_id = :gym_id
