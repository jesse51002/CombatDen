-- Staff redeem-for-member SMART path: if the member already has an OPEN
-- PENDING redemption for this reward, approve the OLDEST one instead of
-- minting (and debiting) a brand-new redemption — the pending row already
-- debited the points at request time.
--
-- Returns the full redemption row shape (points_balance_after = the
-- member's CURRENT balance; an approve never moves points) or 0 rows when
-- the member has no pending redemption for this reward — the service then
-- falls through to the normal redeem / override path.
--
-- Same construction as reject_redemption.sql: the pending guard lives ONLY
-- in the locked CTE (SELECT ... FOR UPDATE) and the UPDATE consumes it via
-- FROM, never re-checking status against a row version another transaction
-- just wrote. A concurrent decision makes the locked SELECT's re-evaluated
-- WHERE exclude the row -> 0 rows -> fresh-redeem fallback.
-- Bind params: :member_id, :reward_id
WITH locked_pending AS (
    SELECT redemption_id
    FROM member_reward_redemptions
    WHERE member_id = CAST(:member_id AS UUID)
      AND reward_id = CAST(:reward_id AS UUID)
      AND status = CAST('pending' AS reward_redemption_status)
    ORDER BY requested_at
    LIMIT 1
    FOR UPDATE
),
approved AS (
    UPDATE member_reward_redemptions mrr
    SET
        status      = CAST('approved' AS reward_redemption_status),
        resolved_at = now()
    FROM locked_pending lp
    WHERE mrr.redemption_id = lp.redemption_id
    RETURNING
        mrr.redemption_id, mrr.member_id, mrr.reward_id, mrr.gym_id,
        mrr.point_cost, mrr.requested_at, mrr.status, mrr.resolved_at
)
SELECT
    a.redemption_id,
    a.member_id,
    a.reward_id,
    a.gym_id,
    a.point_cost,
    a.requested_at,
    a.status,
    a.resolved_at,
    m.points_balance AS points_balance_after
FROM approved a
JOIN members m ON m.member_id = a.member_id
