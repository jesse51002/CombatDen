-- List the gym's owner-facing membership plans in the CRM display order, so
-- the preset import can cycle the imported class photos onto them.
--
-- Reads the filtered membership_plans view (stripe_product_id IS NOT NULL)
-- plus is_deleted = false, so ONLY plans that actually surface to owners are
-- returned -- a pending/half-synced plan (no Stripe product yet) or a
-- soft-deleted plan never gets a preset image assigned. The order mirrors
-- src/plans/sql/membership_plans_list.sql (created_at DESC = newest first);
-- plan_id is a deterministic tiebreaker so the image cycle is stable across
-- re-imports even when two plans share a created_at.
SELECT plan_id
FROM membership_plans
WHERE gym_id = CAST(:gym_id AS UUID)
  AND is_deleted = false
ORDER BY created_at DESC, plan_id
