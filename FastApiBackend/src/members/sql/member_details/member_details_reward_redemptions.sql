SELECT
    rr.redemption_id,
    rr.reward_id,
    rr.point_cost,
    rr.redeemed_at,
    r.title,
    r.amount_off,
    r.image_url
FROM user_gym_reward_redemptions rr
JOIN gym_rewards r ON r.reward_id = rr.reward_id
WHERE rr.gym_id = :gym_id
    AND rr.crm_user_id = :crm_user_id
ORDER BY rr.redeemed_at DESC
