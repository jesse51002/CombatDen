-- Hand-authored migration.
-- Replaces gym_waivers.is_default (a single boolean flag for the one
-- undeletable authorized-payer waiver) with an expandable waiver_type enum
-- ('payer_auth' | 'custom'). is_default only ever meant "this is the
-- authorized-payer agreement" — a boolean can't grow past that binary, but
-- the waiver catalog is expected to gain more backend-owned special-purpose
-- types over time, so the flag becomes an enum column now while there is
-- exactly one special-purpose value.
--
--   1. CREATE TYPE waiver_type ('payer_auth', 'custom').
--   2. Add gym_waivers.waiver_type NOT NULL DEFAULT 'custom'.
--   3. Backfill: is_default = true rows become waiver_type = 'payer_auth'.
--   4. Drop the old is_default machinery (trg_prevent_default_waiver_removal,
--      prevent_default_waiver_removal(), idx_gym_waivers_one_default).
--   5. Create the new machinery keyed on waiver_type
--      (idx_gym_waivers_one_payer_auth, protect_payer_auth_waiver(),
--      trg_protect_payer_auth_waiver) — same client-tamper protection
--      (client roles can't archive/delete a payer_auth waiver; service_role
--      may hard-delete during gym-create teardown), plus waiver_type is
--      immutable for ALL roles once set.
--   6. Re-apply client-write REVOKEs on the new waiver_type column (the old
--      is_default REVOKEs disappear automatically when the column is
--      dropped; the waiver_id/gym_id/created_at REVOKEs from 20260622233350
--      are untouched since those columns are unchanged).
--   7. Drop the now-unused is_default column.
--
-- Mirrors schemas/gym_waivers.sql and access_rules/gym_waivers.sql (end
-- state). No views reference gym_waivers; nothing else to drop/recreate.

-- ── 1. waiver_type enum ─────────────────────────────────────────────────────

CREATE TYPE waiver_type AS ENUM ('payer_auth', 'custom');

-- ── 2. gym_waivers: add waiver_type ─────────────────────────────────────────

ALTER TABLE gym_waivers
    ADD COLUMN waiver_type waiver_type NOT NULL DEFAULT 'custom';

-- ── 3. Backfill: is_default rows become payer_auth ──────────────────────────

UPDATE gym_waivers
    SET waiver_type = 'payer_auth'
    WHERE is_default = true;

-- ── 4. Drop the old is_default machinery ────────────────────────────────────

DROP TRIGGER IF EXISTS trg_prevent_default_waiver_removal ON gym_waivers;
DROP FUNCTION IF EXISTS prevent_default_waiver_removal();
DROP INDEX IF EXISTS idx_gym_waivers_one_default;

-- ── 5. Create the new waiver_type machinery ─────────────────────────────────

-- At most one payer-auth waiver per gym.
CREATE UNIQUE INDEX idx_gym_waivers_one_payer_auth
    ON gym_waivers (gym_id) WHERE waiver_type = 'payer_auth';

-- The payer-auth waiver is protected from client tampering: gym staff
-- (authenticated / anon) cannot archive (is_deleted) or hard-delete it, and
-- waiver_type is immutable for ALL roles once set. The backend (service_role)
-- may hard-delete a payer-auth waiver during gym-create teardown — if the
-- waiver seeds but the Stripe account create fails, cleanup must be able to
-- remove it so there is no dangling row after the gym is torn down.
CREATE OR REPLACE FUNCTION protect_payer_auth_waiver()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Block hard-delete for client roles only; service_role may delete
        -- during gym teardown (see GymsCreateService._cleanup_pending).
        IF OLD.waiver_type = 'payer_auth'
            AND current_user IN ('authenticated', 'anon') THEN
            RAISE EXCEPTION
                'Cannot delete the payer-auth waiver for gym %', OLD.gym_id;
        END IF;
        RETURN OLD;
    END IF;
    -- UPDATE: block archiving a payer-auth waiver for client roles only.
    IF OLD.waiver_type = 'payer_auth' AND NEW.is_deleted
        AND current_user IN ('authenticated', 'anon') THEN
        RAISE EXCEPTION
            'Cannot archive the payer-auth waiver for gym %', OLD.gym_id;
    END IF;
    -- waiver_type is immutable for ALL roles once set.
    IF OLD.waiver_type <> NEW.waiver_type THEN
        RAISE EXCEPTION
            'waiver_type is immutable on gym_waivers (waiver %)', OLD.waiver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_payer_auth_waiver
    BEFORE UPDATE OR DELETE ON gym_waivers
    FOR EACH ROW
    EXECUTE FUNCTION protect_payer_auth_waiver();

-- ── 6. Access rules: revoke client writes on waiver_type ────────────────────

-- waiver_type is set once at seed/create by service_role and never changed
-- (payer_auth = the undeletable platform-copied authorized-payer agreement),
-- so clients can neither set it on insert (their inserts always default to
-- 'custom') nor change it on update. waiver_id/gym_id/created_at are already
-- revoked by the original REVOKE UPDATE in 20260622233350 and are unaffected
-- by this migration.
REVOKE UPDATE (waiver_type) ON TABLE gym_waivers FROM authenticated;
REVOKE INSERT (waiver_type) ON TABLE gym_waivers FROM authenticated;

-- ── 7. Drop the old is_default column ────────────────────────────────────────

ALTER TABLE gym_waivers DROP COLUMN is_default;
