-- Fetch minimal redemption fields for auth + conflict checking.
-- Bind param: :redemption_id
SELECT
    redemption_id,
    gym_id,
    member_id,
    status
FROM member_reward_redemptions
WHERE redemption_id = CAST(:redemption_id AS UUID)
