-- Gym-wide pending redemption queue, oldest-first.
-- Bind param: :gym_id
SELECT
    rr.redemption_id,
    rr.member_id,
    m.first_name || ' ' || m.last_name AS member_name,
    gr.title                           AS reward_title,
    gr.image_url                       AS reward_image_url,
    rr.point_cost,
    rr.redeemed_at
FROM member_reward_redemptions rr
JOIN gym_rewards gr ON gr.reward_id = rr.reward_id
JOIN members     m  ON m.member_id  = rr.member_id
WHERE rr.gym_id = CAST(:gym_id AS UUID)
  AND rr.status = CAST('pending' AS reward_redemption_status)
ORDER BY rr.redeemed_at ASC
