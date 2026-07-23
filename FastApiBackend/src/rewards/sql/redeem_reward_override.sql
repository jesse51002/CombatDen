-- Staff override redemption: no points guard, drains balance to zero.
-- Debits LEAST(points_balance, point_cost) so balance never goes negative.
-- Always inserts status='approved', resolved_at=now().
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
    -- EVERY guard MUST live here, not only on the insert: Postgres runs each
    -- data-modifying CTE exactly once regardless of whether the final query
    -- reads it, so an unguarded drain zeroes the balance while inserting no
    -- redemption row. That applies to is_active AND to the same-gym check --
    -- the insert's `JOIN locked_reward lr ON lr.gym_id = lm.gym_id` only
    -- suppresses the ROW. This path drains LEAST(balance, cost) with no
    -- sufficiency guard, so a cross-gym reward_id burned points off EVERY
    -- member, not just ones who could afford the reward.
    UPDATE members
    SET points_balance = points_balance - LEAST(
        points_balance,
        (SELECT point_cost FROM locked_reward)
    )
    WHERE member_id = :member_id
      AND (SELECT is_active FROM locked_reward)
      AND (SELECT gym_id FROM locked_reward)
          = (SELECT gym_id FROM locked_member)
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
        CAST('approved' AS reward_redemption_status),
        now()
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
