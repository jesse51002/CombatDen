-- Gym-wide pending redemption queue, oldest-first, paginated.
-- Bind params: :gym_id, :limit, :offset
SELECT
    rr.redemption_id,
    rr.member_id,
    m.first_name || ' ' || m.last_name AS member_name,
    gr.title                           AS reward_title,
    gr.image_url                       AS reward_image_url,
    rr.point_cost,
    rr.requested_at,
    COUNT(*) OVER () AS total
FROM member_reward_redemptions rr
JOIN gym_rewards gr ON gr.reward_id = rr.reward_id
JOIN members     m  ON m.member_id  = rr.member_id
WHERE rr.gym_id = CAST(:gym_id AS UUID)
  AND rr.status = CAST('pending' AS reward_redemption_status)
ORDER BY rr.requested_at ASC
LIMIT :limit OFFSET :offset
