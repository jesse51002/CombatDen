-- Staff override redemption: no points guard, drains balance to zero.
-- Debits LEAST(points_balance, point_cost) so balance never goes negative.
-- Always inserts status='approved', decided_at=now().
-- Bind params: :member_id, :reward_id
WITH locked_member AS (
    SELECT member_id, points_balance, gym_id
    FROM members
    WHERE member_id = :member_id
    FOR UPDATE
),
locked_reward AS (
    SELECT reward_id, point_cost, gym_id, is_active
    FROM gym_rewards
    WHERE reward_id = :reward_id
    FOR UPDATE
),
debited AS (
    -- The is_active guard MUST live here, not only on the insert: Postgres
    -- runs every data-modifying CTE exactly once regardless of whether the
    -- final query reads it, so an unguarded drain on an inactive reward
    -- would zero the balance while inserting no redemption row.
    UPDATE members
    SET points_balance = points_balance - LEAST(
        points_balance,
        (SELECT point_cost FROM locked_reward)
    )
    WHERE member_id = :member_id
      AND (SELECT is_active FROM locked_reward)
    RETURNING points_balance
),
inserted AS (
    INSERT INTO member_reward_redemptions (
        member_id,
        gym_id,
        reward_id,
        point_cost,
        status,
        decided_at
    )
    SELECT
        lm.member_id,
        lm.gym_id,
        lr.reward_id,
        lr.point_cost,
        CAST('approved' AS reward_redemption_status),
        now()
    FROM locked_member lm
    JOIN locked_reward lr ON lr.gym_id = lm.gym_id
    WHERE lr.is_active = TRUE
      AND EXISTS (SELECT 1 FROM debited)
    RETURNING
        redemption_id, member_id, reward_id, gym_id,
        point_cost, redeemed_at, status, decided_at
)
SELECT
    i.redemption_id,
    i.member_id,
    i.reward_id,
    i.gym_id,
    i.point_cost,
    i.redeemed_at,
    i.status,
    i.decided_at,
    d.points_balance AS points_balance_after
FROM inserted i
JOIN debited d ON TRUE
