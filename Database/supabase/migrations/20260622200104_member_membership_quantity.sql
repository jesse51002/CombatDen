-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds `quantity` column to member_memberships_unfiltered with a positive-integer
-- CHECK constraint and a trigger that enforces quantity = 1 for recurring plans.
-- The two dependent views (member_memberships, member_memberships_status) are
-- dropped and recreated in dependency order so their SELECT * picks up the new
-- column. security_invoker = true is preserved on both views and view-level
-- grants/revokes are re-applied (DROP VIEW drops grants).
-- Mirrors schemas/member_memberships.sql.

-- ============================================================
-- 1. Drop dependent views (reverse dependency order)
-- ============================================================

DROP VIEW IF EXISTS member_memberships_status;
DROP VIEW IF EXISTS member_memberships;

-- ============================================================
-- 2. Add quantity column to the base table
-- ============================================================

ALTER TABLE member_memberships_unfiltered
    ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1
        CONSTRAINT member_membership_quantity_positive CHECK (quantity > 0);

-- ============================================================
-- 3. Trigger: recurring plans must have quantity = 1
-- ============================================================

CREATE OR REPLACE FUNCTION check_recurring_quantity_is_one()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.quantity <> 1 THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans_unfiltered
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships must have quantity = 1'
                USING CONSTRAINT = 'recurring_quantity_must_be_one';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_quantity_must_be_one
    BEFORE INSERT OR UPDATE OF quantity ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_quantity_is_one();

-- ============================================================
-- 4. Recreate member_memberships (now includes quantity column)
-- ============================================================

CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

-- Safety net: supabase diff can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships SET (security_invoker = true);

-- ============================================================
-- 5. Recreate member_memberships_status (depends on member_memberships)
-- ============================================================

CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= (now() AT TIME ZONE g.timezone)::date THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= (now() AT TIME ZONE g.timezone)::date THEN 'ended'
        WHEN freeze_owner.freeze_start_date IS NOT NULL
             AND freeze_owner.freeze_end_date IS NOT NULL
             AND freeze_owner.freeze_start_date <= (now() AT TIME ZONE g.timezone)::date
             AND (now() AT TIME ZONE g.timezone)::date <= freeze_owner.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
JOIN members freeze_owner
    ON freeze_owner.member_id = mm.paid_by_member_id;

-- Safety net: supabase diff can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);

-- ============================================================
-- 6. Re-apply view-level grants (DROP VIEW drops all grants)
-- ============================================================
-- member_memberships: authenticated write block (access_rules/member_memberships.sql)
-- + SELECT for both roles (established by 20260617090000_membership_immutability_tasks.sql
-- and carried forward here).
GRANT SELECT ON member_memberships TO authenticated, service_role;
REVOKE INSERT, UPDATE ON member_memberships FROM authenticated;

-- member_memberships_status: no writes are expected; restore SELECT for both
-- roles (established by 20260617090000_membership_immutability_tasks.sql).
GRANT SELECT ON member_memberships_status TO authenticated, service_role;
