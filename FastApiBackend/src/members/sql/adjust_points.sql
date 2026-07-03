-- Lock the member row first, then apply the signed adjustment only when
-- the result would not go below zero. An empty result means either the
-- member does not exist or the adjustment would underflow.
WITH lock AS (
    SELECT member_id
    FROM members
    WHERE member_id = CAST(:member_id AS UUID)
    FOR UPDATE
)
UPDATE members
SET points_balance = points_balance + :amount
FROM lock
WHERE members.member_id = lock.member_id
    AND members.points_balance + :amount >= 0
RETURNING members.points_balance
