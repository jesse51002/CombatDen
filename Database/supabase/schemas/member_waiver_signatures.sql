-- Append-only e-signature audit records: a member signed a SPECIFIC waiver
-- version, with the evidence a US e-sign record (ESIGN/UETA) leans on — signer
-- identity (member + typed legal name), intent + consent (consent_acknowledged),
-- integrity (waiver_version_id + content_hash freeze the exact wording), and the
-- when/where (signed_at UTC, ip_address, user_agent). Rows are never updated or
-- deleted (REVOKE UPDATE, DELETE) so the legal record is tamper-evident.
--
-- Phase 1 builds this table + READ endpoints only; the front-desk clickwrap
-- capture (the INSERT path) is Phase 2, which also adds the INSERT RLS policy.

-- Signature capture method. Phase 1 captures typed clickwrap only; the enum is
-- extensible (e.g. 'drawn', 'uploaded') without a schema break.
CREATE TYPE waiver_signature_type AS ENUM ('typed');

CREATE TABLE member_waiver_signatures (
    signature_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_waiver_sig_gym REFERENCES gyms(gym_id),
    member_id UUID NOT NULL,
    waiver_id UUID NOT NULL,
    waiver_version_id UUID NOT NULL,
    signed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    signer_name VARCHAR NOT NULL CHECK (signer_name <> ''),
    signature_type waiver_signature_type NOT NULL DEFAULT 'typed',
    consent_acknowledged BOOLEAN NOT NULL,
    ip_address INET,
    user_agent VARCHAR,
    content_hash VARCHAR NOT NULL CHECK (content_hash <> ''),
    PRIMARY KEY (signature_id),

    -- A valid e-signature requires affirmative consent.
    CONSTRAINT chk_waiver_sig_consent CHECK (consent_acknowledged = true),

    CONSTRAINT fk_waiver_sig_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    CONSTRAINT fk_waiver_sig_waiver_gym
        FOREIGN KEY (waiver_id, gym_id)
        REFERENCES gym_waivers (waiver_id, gym_id),

    CONSTRAINT fk_waiver_sig_version_gym
        FOREIGN KEY (waiver_version_id, gym_id)
        REFERENCES gym_waiver_versions (version_id, gym_id)
);

CREATE INDEX idx_member_waiver_signatures_member
    ON member_waiver_signatures (member_id, gym_id);
CREATE INDEX idx_member_waiver_signatures_waiver
    ON member_waiver_signatures (waiver_id);
CREATE INDEX idx_member_waiver_signatures_version
    ON member_waiver_signatures (waiver_version_id);
