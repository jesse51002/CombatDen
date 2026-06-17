-- Reprice: cancel the old row effective TODAY — unlike the normal cancel's
-- GREATEST(next_due_date, today), because billing switches to the successor
-- row in the SAME converge (prorated per the request) and the recurring
-- INSERT gates admit the successor only once the old row's cancellation is
-- already effective. Runs inside the reprice transaction on the caller's
-- session (no commit here); the writeback stamps 'deleted' after the
-- converge.
UPDATE member_memberships_unfiltered
SET cancel_date = CAST(:gym_today AS DATE)
WHERE item_id = :item_id
  AND member_id = :member_id
