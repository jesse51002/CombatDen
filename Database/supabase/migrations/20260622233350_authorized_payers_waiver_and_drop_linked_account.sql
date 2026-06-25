-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Piece 1: add is_default + undeletable-default machinery to gym_waivers;
--   add INSERT policy for gym staff on member_waiver_signatures;
--   create member_authorized_payers (authorization layer, replaces single-parent link).
-- Piece 2C: drop members.account_linked_to_id and all dependents
--   (trigger, function, index, FK constraint), then recreate member_billing_profile
--   as SELECT * FROM members (dropping the explicit-column version that listed
--   account_linked_to_id) and re-apply its grants.
-- Mirrors schemas/member_authorized_payers.sql, schemas/gym_waivers.sql,
--   access_rules/member_authorized_payers.sql, access_rules/gym_waivers.sql,
--   access_rules/member_waiver_signatures.sql, schemas/members.sql,
--   access_rules/members.sql.

-- ============================================================
-- 1. gym_waivers: add is_default column + one-default index +
--    undeletable-default trigger
-- ============================================================

ALTER TABLE gym_waivers
    ADD COLUMN is_default BOOLEAN NOT NULL DEFAULT FALSE;

-- At most one default waiver per gym.
CREATE UNIQUE INDEX idx_gym_waivers_one_default
    ON gym_waivers (gym_id) WHERE is_default = true;

-- The default waiver is undeletable: it can be edited (which versions normally
-- via gym_waiver_versions) but never archived (is_deleted) or hard-deleted, and
-- is_default itself is fixed once set. Enforced for ALL roles (incl.
-- service_role) so the authorized-payer gate always has a document to sign.
CREATE OR REPLACE FUNCTION prevent_default_waiver_removal()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.is_default THEN
            RAISE EXCEPTION
                'Cannot delete the default waiver for gym %', OLD.gym_id;
        END IF;
        RETURN OLD;
    END IF;
    -- UPDATE: block archiving a default and block toggling is_default.
    IF OLD.is_default AND NEW.is_deleted THEN
        RAISE EXCEPTION
            'Cannot archive the default waiver for gym %', OLD.gym_id;
    END IF;
    IF OLD.is_default <> NEW.is_default THEN
        RAISE EXCEPTION
            'is_default is immutable on gym_waivers (waiver %)', OLD.waiver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_default_waiver_removal
    BEFORE UPDATE OR DELETE ON gym_waivers
    FOR EACH ROW
    EXECUTE FUNCTION prevent_default_waiver_removal();

-- ============================================================
-- 2. gym_waivers access rules: revoke is_default from clients
-- ============================================================

-- Identity columns stay immutable; the default flag is set once at seed/create
-- by service_role and never changed (the undeletable platform-copied default),
-- so clients can neither set it on insert nor change it on update.
REVOKE UPDATE (waiver_id, gym_id, created_at, is_default)
    ON TABLE gym_waivers FROM authenticated;
REVOKE INSERT (is_default) ON TABLE gym_waivers FROM authenticated;

-- ============================================================
-- 3. member_waiver_signatures: add INSERT policy for gym staff
-- ============================================================

-- Gym staff record signatures at the front desk (clickwrap capture).
CREATE POLICY "Gym staff can record waiver signatures"
    ON member_waiver_signatures
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_waiver_signatures.gym_id));

-- ============================================================
-- 4. member_authorized_payers: create table + indexes
-- ============================================================

CREATE TABLE member_authorized_payers (
    member_id UUID NOT NULL,
    payer_member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_authpayer_gym REFERENCES gyms(gym_id),
    signature_id UUID NOT NULL
        CONSTRAINT fk_authpayer_signature
        REFERENCES member_waiver_signatures(signature_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (member_id, payer_member_id),

    -- A member never authorizes themselves — self-pay needs no row.
    CONSTRAINT chk_authpayer_distinct CHECK (member_id <> payer_member_id),

    CONSTRAINT fk_authpayer_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    CONSTRAINT fk_authpayer_payer_gym
        FOREIGN KEY (payer_member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- Both directions are read: "who may pay for me" (member_id) and "who am I
-- authorized to pay for" (payer_member_id).
CREATE INDEX idx_authpayer_member
    ON member_authorized_payers (member_id, gym_id);
CREATE INDEX idx_authpayer_payer
    ON member_authorized_payers (payer_member_id, gym_id);

-- ============================================================
-- 5. member_authorized_payers access rules
-- ============================================================

-- Enable Row Level Security
ALTER TABLE member_authorized_payers ENABLE ROW LEVEL SECURITY;

-- Gym staff see everything at their gym; involved members see their own links.
CREATE POLICY "Gym staff and involved members can view authorized payers"
    ON member_authorized_payers
    FOR SELECT
    USING (
        is_gym_admin_or_owner(member_authorized_payers.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.user_id = auth.uid()
            AND members.member_id IN (
                member_authorized_payers.member_id,
                member_authorized_payers.payer_member_id
            )
        )
    );

-- Backend-managed via service_role — clients never insert/update/delete.
REVOKE INSERT, UPDATE, DELETE
    ON TABLE member_authorized_payers FROM authenticated;

-- ============================================================
-- 6. Drop account_linked_to_id and all dependents from members
-- ============================================================

-- 6a. Drop member_billing_profile: it is SELECT * FROM members (or an
--     explicit-column equivalent that lists account_linked_to_id), so Postgres
--     pins the column list and the DROP COLUMN below will fail while the view
--     exists.
DROP VIEW IF EXISTS member_billing_profile;

-- 6b. Drop the trigger and function that enforced the hierarchy.
DROP TRIGGER IF EXISTS trg_enforce_linked_account_hierarchy ON members;
DROP FUNCTION IF EXISTS enforce_linked_account_hierarchy();

-- 6c. Drop the index added in 20260607104931_update.sql.
DROP INDEX IF EXISTS idx_members_account_linked_to;

-- 6d. Drop the FK constraint (added in 20260603202943_start.sql).
ALTER TABLE members DROP CONSTRAINT IF EXISTS fk_member_linked_account;

-- 6e. Drop the column itself.
ALTER TABLE members DROP COLUMN IF EXISTS account_linked_to_id;

-- ============================================================
-- 7. Recreate member_billing_profile as SELECT * FROM members
-- ============================================================

-- Filtered view: members with a completed Stripe customer sync. Billing flows
-- read through this so half-synced rows are never surfaced. `members` is the
-- single source-of-truth table; this is just a billing-complete window onto it.
CREATE VIEW member_billing_profile
WITH (security_invoker = true)
AS
SELECT * FROM members WHERE stripe_customer_id IS NOT NULL;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_billing_profile SET (security_invoker = true);

-- ============================================================
-- 8. Re-apply member_billing_profile grants (DROP VIEW drops all grants)
-- ============================================================

-- Filtered billing view: read-only for clients (writes go to the members
-- table via service_role). security_invoker propagates members' RLS.
GRANT SELECT ON member_billing_profile TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON member_billing_profile FROM authenticated;
