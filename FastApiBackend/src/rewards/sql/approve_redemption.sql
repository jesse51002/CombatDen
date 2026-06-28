-- Approve a pending redemption. Idempotent: no-op (returns no row) when
-- status is not 'pending'. Bind param: :redemption_id
UPDATE member_reward_redemptions
SET
    status     = CAST('approved' AS reward_redemption_status),
    decided_at = now()
WHERE redemption_id = CAST(:redemption_id AS UUID)
  AND status = CAST('pending' AS reward_redemption_status)
RETURNING
    redemption_id,
    member_id,
    reward_id,
    gym_id,
    point_cost,
    status,
    decided_at
