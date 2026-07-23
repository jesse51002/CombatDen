-- Raw reward redemption log for the gym (point_cost is the snapshot at request
-- time).
SELECT
    rr.redemption_id,
    rr.gym_id,
    rr.member_id,
    rr.reward_id,
    rr.point_cost,
    rr.requested_at,
    rr.status,
    rr.resolved_at
FROM member_reward_redemptions rr
WHERE rr.gym_id = CAST(:gym_id AS UUID)
ORDER BY rr.requested_at ASC, rr.redemption_id ASC
