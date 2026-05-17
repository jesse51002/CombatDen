SELECT
    r.redemption_id,
    r.reward_id,
    r.point_cost,
    r.redeemed_at,
    gr.title,
    gr.image_url,
    gr.amount_off
FROM member_reward_redemptions r
JOIN gym_rewards gr ON gr.reward_id = r.reward_id
WHERE r.member_id = :member_id
ORDER BY r.redeemed_at DESC
LIMIT 100
