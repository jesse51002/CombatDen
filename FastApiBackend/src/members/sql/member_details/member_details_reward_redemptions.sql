SELECT
    rr.redemption_id,
    rr.reward_id,
    rr.point_cost,
    rr.requested_at,
    r.title,
    r.price_label,
    r.image_url
FROM member_reward_redemptions rr
JOIN gym_rewards r ON r.reward_id = rr.reward_id
WHERE rr.gym_id = :gym_id
    AND rr.member_id = :member_id
    AND rr.status = 'approved'
ORDER BY rr.requested_at DESC
LIMIT 20
