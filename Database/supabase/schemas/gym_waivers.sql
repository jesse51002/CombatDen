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
CREATE TABLE gym_waivers (
    waiver_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_waiver_gym REFERENCES gyms(gym_id),
    name VARCHAR NOT NULL CHECK (name <> ''),
    current_version_id UUID,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    -- The undeletable default authorized-payer waiver (one per gym). Seeded as a
    -- copy of the platform default; editable like any waiver, but never archived
    -- or deleted (trg_prevent_default_waiver_removal) so the authorized-payer
    -- gate always has a document to sign.
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (waiver_id),
    UNIQUE (waiver_id, gym_id)
);

CREATE INDEX idx_gym_waivers_gym ON gym_waivers (gym_id) WHERE is_deleted = false;

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
