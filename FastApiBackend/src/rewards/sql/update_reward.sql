UPDATE gym_rewards
SET {set_clause}
WHERE reward_id = :reward_id
RETURNING
    reward_id,
    gym_id,
    title,
    point_cost,
    amount_off,
    image_url,
    price_label,
    is_active,
    created_at
