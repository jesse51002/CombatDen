-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Removes the linked (family) discount feature from the schema:
--   1. Drops `linked_discount_enabled` and `linked_discount_ids` columns from
--      membership_plans_unfiltered (the named CHECK chk_plan_linked_ids_array
--      drops automatically with its column).
--   2. Retires the 'linked' value from gym_discounts_unfiltered.discount_type
--      (was IN ('preset','custom','linked'), now IN ('preset','custom')).
-- The membership_plans view is SELECT * so it must be dropped and recreated
-- around the column drops. The gym_discounts view is a plain passthrough and
-- does NOT need recreating for a CHECK change.
-- Mirrors schemas/membership_plans.sql and schemas/gym_discounts.sql.

-- ============================================================
-- 1. Drop membership_plans view (depends on all columns via SELECT *)
-- ============================================================

DROP VIEW IF EXISTS membership_plans;

-- ============================================================
-- 2. Drop linked-discount columns from membership_plans_unfiltered
--    (chk_plan_linked_ids_array drops automatically with linked_discount_ids)
-- ============================================================

ALTER TABLE membership_plans_unfiltered
    DROP COLUMN IF EXISTS linked_discount_enabled,
    DROP COLUMN IF EXISTS linked_discount_ids;

-- ============================================================
-- 3. Recreate membership_plans view (security_invoker preserved)
-- ============================================================

CREATE VIEW membership_plans
WITH (security_invoker = true)
AS
SELECT * FROM membership_plans_unfiltered
WHERE stripe_product_id IS NOT NULL;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW membership_plans SET (security_invoker = true);

-- Re-apply view-level grants (DROP VIEW drops all grants)
REVOKE INSERT, UPDATE ON membership_plans FROM authenticated;

-- ============================================================
-- 4. Retire 'linked' from gym_discounts_unfiltered.discount_type
-- ============================================================

-- Belt-and-suspenders: remove any 'linked' rows before tightening the CHECK.
-- Confirmed no such rows exist in production, so this is a no-op in practice.
DELETE FROM gym_discounts_unfiltered WHERE discount_type = 'linked';

ALTER TABLE gym_discounts_unfiltered
    DROP CONSTRAINT gym_discounts_unfiltered_discount_type_check;

ALTER TABLE gym_discounts_unfiltered
    ADD CONSTRAINT gym_discounts_unfiltered_discount_type_check
        CHECK (discount_type IN ('preset', 'custom'));
