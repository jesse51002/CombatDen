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
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (waiver_id),
    UNIQUE (waiver_id, gym_id)
);

CREATE INDEX idx_gym_waivers_gym ON gym_waivers (gym_id) WHERE is_deleted = false;
