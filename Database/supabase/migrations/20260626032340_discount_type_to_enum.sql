-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Converts gym_discounts_unfiltered.discount_type from a VARCHAR CHECK constraint
-- to a real Postgres enum, satisfying Database/CLAUDE.md's "always use real Postgres
-- enums, never CHECK (col IN ...)" rule. The CHECK approach used by the prior migration
-- was a temporary step; this migration reaches the end state declared in
-- schemas/gym_discounts.sql (discount_type AS ENUM ('preset', 'custom')).

-- ============================================================
-- 1. Create the enum type
-- ============================================================

CREATE TYPE discount_type AS ENUM ('preset', 'custom');

-- ============================================================
-- 2. Drop the gym_discounts view
--    (SELECT * depends on the column; must be gone before ALTER COLUMN TYPE)
-- ============================================================

DROP VIEW IF EXISTS gym_discounts;

-- ============================================================
-- 3. Drop the CHECK constraint left by the previous migration
-- ============================================================

ALTER TABLE gym_discounts_unfiltered
    DROP CONSTRAINT gym_discounts_unfiltered_discount_type_check;

-- ============================================================
-- 4. Convert the column to the new enum type
--    All existing values are 'preset' or 'custom' — the USING cast is safe.
-- ============================================================

ALTER TABLE gym_discounts_unfiltered
    ALTER COLUMN discount_type TYPE discount_type
    USING discount_type::discount_type;

-- ============================================================
-- 5. Recreate the gym_discounts view (security_invoker mandatory)
--    Mirrors schemas/gym_discounts.sql exactly.
-- ============================================================

CREATE VIEW gym_discounts
WITH (security_invoker = true)
AS
SELECT * FROM gym_discounts_unfiltered;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW gym_discounts SET (security_invoker = true);

-- ============================================================
-- 6. Restore view-level grants (DROP VIEW drops all grants)
-- ============================================================

REVOKE INSERT, UPDATE, DELETE ON gym_discounts FROM authenticated;
