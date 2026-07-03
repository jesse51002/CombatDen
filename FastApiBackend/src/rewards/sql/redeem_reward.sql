-- Single statement that atomically:
--   1) decrements points_balance (guarded: only if balance >= point_cost)
--   2) inserts a row in member_reward_redemptions with the given status
-- Uses a CTE so both writes share one transactional unit.
-- Bind params: :member_id, :reward_id, :status ('pending' or 'approved')
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
    -- final query reads it, so an unguarded debit on an inactive reward
    -- would burn points while inserting no redemption row.
    UPDATE members
    SET points_balance = points_balance - (
        SELECT point_cost FROM locked_reward
    )
    WHERE member_id = :member_id
      AND points_balance >= (SELECT point_cost FROM locked_reward)
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
        resolved_at
    )
    SELECT
        lm.member_id,
        lm.gym_id,
        lr.reward_id,
        lr.point_cost,
        CAST(:status AS reward_redemption_status),
        CASE WHEN :status = 'approved' THEN now() ELSE NULL END
    FROM locked_member lm
    JOIN locked_reward lr ON lr.gym_id = lm.gym_id
    -- Gate on the debit by consuming its RETURNING in the FROM clause (the
    -- documented way to chain data-modifying CTEs). An EXISTS(SELECT FROM
    -- debited) here evaluated FALSE on live Postgres even when the debit
    -- happened — cross-referencing a data-modifying CTE from another one's
    -- WHERE is not reliably ordered.
    JOIN debited d ON TRUE
    WHERE lr.is_active = TRUE
    RETURNING
        redemption_id, member_id, reward_id, gym_id,
        point_cost, requested_at, status, resolved_at
)
SELECT
    i.redemption_id,
    i.member_id,
    i.reward_id,
    i.gym_id,
    i.point_cost,
    i.requested_at,
    i.status,
    i.resolved_at,
    d.points_balance AS points_balance_after
FROM inserted i
JOIN debited d ON TRUE
