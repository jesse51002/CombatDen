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
WHERE gym_id = :gym_id
  AND ({include_inactive} OR is_active = TRUE)
ORDER BY point_cost ASC
