-- Raw reward catalog for the gym.
SELECT
    r.reward_id,
    r.gym_id,
    r.title,
    r.price_label,
    r.image_url,
    r.point_cost,
    r.is_active,
    r.created_at
FROM gym_rewards r
WHERE r.gym_id = CAST(:gym_id AS UUID)
ORDER BY r.created_at ASC, r.reward_id ASC
