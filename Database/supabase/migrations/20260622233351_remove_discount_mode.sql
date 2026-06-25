-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Removes the `discount_mode` column (and its enum type) from
-- gym_discount_values_unfiltered. Adds `cycle` to discount_duration_unit
-- (via type-recreate — ALTER TYPE … ADD VALUE can't run inside a transaction).
-- Data-migrates legacy `once` rows to a 1-cycle span before the column is
-- dropped. Drops and recreates the gym_discount_values view (which depends on
-- duration_unit AND discount_mode) with security_invoker = true.
-- Mirrors schemas/gym_discount_values.sql (end state).

-- ============================================================
-- 1. Drop the gym_discount_values view FIRST.
--    It is SELECT * (expanded to explicit columns in its _RETURN rule, incl.
--    duration_unit AND discount_mode), so it pins a dependency on those columns.
--    BOTH the duration_unit type-repoint (2c) AND the discount_mode column drop
--    (4a) fail with "cannot alter type of a column used by a view / rule" while
--    the view exists. No other view depends on it, so DROP without CASCADE.
--    Recreated with security_invoker at the end.
-- ============================================================

DROP VIEW IF EXISTS gym_discount_values;

-- ============================================================
-- 2. Recreate discount_duration_unit with `cycle` added
--    (type-recreate pattern: rename old → create new → repoint column → drop old)
-- ============================================================

-- 2a. Rename the existing enum to a temp name so we can create the new one.
ALTER TYPE discount_duration_unit RENAME TO discount_duration_unit_old;

-- 2b. Create the new enum with all four values in the canonical order.
CREATE TYPE discount_duration_unit AS ENUM ('day', 'week', 'month', 'cycle');

-- 2c. Repoint the duration_unit column from the old type to the new one.
--     The USING cast relies on the label-text identity between old and new values
--     ('day'/'week'/'month' exist in both; NULL maps to NULL).
ALTER TABLE gym_discount_values_unfiltered
    ALTER COLUMN duration_unit
        TYPE discount_duration_unit
        USING duration_unit::text::discount_duration_unit;

-- 2d. Drop the old enum — all columns have been repointed.
DROP TYPE discount_duration_unit_old;

-- ============================================================
-- 3. Data migration: convert `once` rows to a 1-cycle span
--    BEFORE dropping the column (while discount_mode still exists).
--    Only touches rows with no other lifetime set (no duration_amount
--    or end_date) so they preserve their single-invoice semantics.
-- ============================================================

UPDATE gym_discount_values_unfiltered
   SET duration_amount = 1,
       duration_unit   = 'cycle'
 WHERE discount_mode = 'once'
   AND duration_amount IS NULL
   AND end_date IS NULL;

-- ============================================================
-- 4. Drop the discount_mode column, then the enum type
-- ============================================================

-- 4a. Drop the column from the base table.
ALTER TABLE gym_discount_values_unfiltered
    DROP COLUMN discount_mode;

-- 4b. Drop the now-unused enum type.
DROP TYPE discount_mode;

-- ============================================================
-- 5. Recreate gym_discount_values as SELECT * (security_invoker)
--    Matches the end state in schemas/gym_discount_values.sql:
--      SELECT * FROM gym_discount_values_unfiltered
-- ============================================================

CREATE VIEW gym_discount_values
WITH (security_invoker = true)
AS
SELECT * FROM gym_discount_values_unfiltered;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW gym_discount_values SET (security_invoker = true);

-- ============================================================
-- 6. Re-apply grants on gym_discount_values (DROP VIEW drops all grants)
-- ============================================================

-- Authenticated users: SELECT only (service_role-write-only, no Stripe gate).
GRANT SELECT ON gym_discount_values TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON gym_discount_values FROM authenticated;
