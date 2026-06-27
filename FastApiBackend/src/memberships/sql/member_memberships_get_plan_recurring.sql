-- The target plan's recurring window, for the cross-plan upgrade guard.
-- A cross-plan upgrade only nets cleanly when the old and new prices bill on
-- the SAME recurring interval (so Stripe prorates both against one period),
-- so the upgrade op compares this against the old membership's plan window
-- (already carried on member_memberships_get.sql). Today every recurring plan
-- is forced monthly by the recurring_must_be_monthly CHECK, so the guard is a
-- no-op now — it exists to stay correct if per-plan intervals ever land.
SELECT
    plan_type,
    duration_unit,
    duration_amount,
    is_deleted
FROM membership_plans
WHERE plan_id = :plan_id
  AND gym_id  = :gym_id
