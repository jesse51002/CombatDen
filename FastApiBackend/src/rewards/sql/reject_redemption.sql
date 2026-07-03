-- Reject a pending redemption and refund the member's points atomically.
-- The pending guard lives ONLY in locked_redemption (SELECT ... FOR UPDATE);
-- both updates consume its RETURNING via their FROM clause, so they fire
-- if-and-only-if a pending row was locked (empty → both no-op → final SELECT
-- returns no row → service raises 409 for double-reject / approve-then-reject).
--
-- Deliberately NOT re-checking status='pending' inside the UPDATEs: CTE
-- execution order is unpredictable, and a same-row re-check runs EvalPlanQual
-- against the row version another CTE just wrote — on live Postgres that
-- marked the row rejected WITHOUT refunding. Chaining through the FROM clause
-- is the documented-reliable way to order data-modifying CTEs.
-- Bind param: :redemption_id
WITH locked_redemption AS (
    SELECT redemption_id, member_id, reward_id, gym_id, point_cost
    FROM member_reward_redemptions
    WHERE redemption_id = CAST(:redemption_id AS UUID)
      AND status = CAST('pending' AS reward_redemption_status)
    FOR UPDATE
),
refunded AS (
    UPDATE members m
    SET points_balance = m.points_balance + lr.point_cost
    FROM locked_redemption lr
    WHERE m.member_id = lr.member_id
    RETURNING m.points_balance
),
rejected AS (
    UPDATE member_reward_redemptions mrr
    SET
        status      = CAST('rejected' AS reward_redemption_status),
        resolved_at = now()
    FROM locked_redemption lr
    WHERE mrr.redemption_id = lr.redemption_id
    RETURNING
        mrr.redemption_id, mrr.member_id, mrr.reward_id, mrr.gym_id,
        mrr.point_cost, mrr.status, mrr.resolved_at
)
SELECT
    r.redemption_id,
    r.member_id,
    r.reward_id,
    r.gym_id,
    r.point_cost,
    r.status,
    r.resolved_at,
    f.points_balance AS points_balance_after
FROM rejected r
JOIN refunded f ON TRUE
