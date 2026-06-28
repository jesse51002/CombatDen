-- Reject a pending redemption and refund the member's points atomically.
-- Guard on status='pending' in every CTE — double-reject / approve-then-reject
-- is a no-op (locked_redemption returns empty → refunded + rejected no-op →
-- final SELECT returns no row → service raises 409).
-- Bind param: :redemption_id
WITH locked_redemption AS (
    SELECT redemption_id, member_id, reward_id, gym_id, point_cost
    FROM member_reward_redemptions
    WHERE redemption_id = CAST(:redemption_id AS UUID)
      AND status = CAST('pending' AS reward_redemption_status)
    FOR UPDATE
),
refunded AS (
    UPDATE members
    SET points_balance = points_balance + (SELECT point_cost FROM locked_redemption)
    WHERE member_id = (SELECT member_id FROM locked_redemption)
    RETURNING points_balance
),
rejected AS (
    UPDATE member_reward_redemptions
    SET
        status     = CAST('rejected' AS reward_redemption_status),
        decided_at = now()
    WHERE redemption_id = CAST(:redemption_id AS UUID)
      AND status = CAST('pending' AS reward_redemption_status)
    RETURNING
        redemption_id, member_id, reward_id, gym_id,
        point_cost, status, decided_at
)
SELECT
    r.redemption_id,
    r.member_id,
    r.reward_id,
    r.gym_id,
    r.point_cost,
    r.status,
    r.decided_at,
    f.points_balance AS points_balance_after
FROM rejected r
JOIN refunded f ON TRUE
