SELECT
    r.redemption_id,
    r.reward_id,
    r.point_cost,
    r.requested_at,
    r.status,
    gr.title,
    gr.image_url,
    gr.price_label
FROM member_reward_redemptions r
JOIN gym_rewards gr ON gr.reward_id = r.reward_id
WHERE r.member_id = :member_id
ORDER BY r.requested_at DESC
LIMIT 100
