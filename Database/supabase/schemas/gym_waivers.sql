-- Gym waiver catalog — the liability/acknowledgment documents a gym requires.
--
-- A waiver is a named document whose TEXT is versioned: each edit to the body
-- publishes a new immutable row in gym_waiver_versions, and members sign a
-- SPECIFIC version (member_waiver_signatures). This table holds only the
-- waiver's identity + a pointer to the current version; the text lives on the
-- versions table so the exact signed wording is preserved for the legal record.
--
-- Plain gym config (no Stripe): gym staff author waivers directly. Gated like
-- gym_classes / gym_rewards (see access_rules/gym_waivers.sql). Soft-deleted via
-- is_deleted so historical versions + signatures survive an archive.
--
-- current_version_id is a forward reference to gym_waiver_versions (which loads
-- after this file), so its FK is declared via ALTER TABLE at the bottom of
-- gym_waiver_versions.sql rather than inline here.

-- What a waiver is FOR. 'custom' = a gym-authored document attachable to
-- membership plans (the purchase gate); special-purpose types are backend-owned
-- and never plan-attachable. Expandable — more special-purpose types may follow.
CREATE TYPE waiver_type AS ENUM ('payer_auth', 'custom');

CREATE TABLE gym_waivers (
    waiver_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_waiver_gym REFERENCES gyms(gym_id),
    name VARCHAR NOT NULL CHECK (name <> ''),
    current_version_id UUID,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    -- 'payer_auth' = the gym's one undeletable authorized-payer agreement
    -- (signed in the authorize-payer link flow). Seeded as a copy of the
    -- platform default; editable like any waiver, but never archived or
    -- deleted (trg_protect_payer_auth_waiver) so the authorized-payer gate
    -- always has a document to sign. Set at seed/create by the backend
    -- (service_role) and immutable thereafter.
    waiver_type waiver_type NOT NULL DEFAULT 'custom',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (waiver_id),
    UNIQUE (waiver_id, gym_id)
);

CREATE INDEX idx_gym_waivers_gym ON gym_waivers (gym_id) WHERE is_deleted = false;

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
