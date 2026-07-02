-- Append-only e-signature audit records: a member signed a SPECIFIC waiver
-- version, with the evidence a US e-sign record (ESIGN/UETA) leans on — signer
-- identity (member + typed legal name), intent + consent (consent_acknowledged),
-- electronic-records consent (esign_disclosure_version pins which versioned
-- disclosure the signer agreed to), integrity (rendered_body is the EXACT text
-- agreed to — the version's template with its {{placeholders}} filled in — and
-- content_hash is the sha256 of that rendered text; waiver_version_id still FKs
-- the immutable template version), and the when/where/who (signed_at UTC,
-- ip_address, user_agent, and operator_employee_id — the staff member who
-- captured the in-person signature). Rows are never updated or deleted (REVOKE
-- UPDATE, DELETE) so the legal record is tamper-evident.
--
-- Signatures are recorded by gym staff (INSERT RLS policy) and by the backend
-- (service_role): the standalone signing endpoint records its own committed row,
-- and the authorized-payer link flow records the payer's signature in the same
-- transaction as the member_authorized_payers insert.

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
    -- Audit trail: now NOT NULL (the capture paths always supply them; legacy
    -- NULLs are backfilled to a sentinel in the hardening migration).
    ip_address INET NOT NULL,
    user_agent VARCHAR NOT NULL,
    -- The EXACT text the signer agreed to: the version template with its
    -- {{placeholders}} (member_name / signer_name / gym_name / date / payee_name)
    -- filled in. content_hash is the sha256 of THIS rendered text (not the
    -- template), so a signature reproduces the agreement standalone.
    rendered_body TEXT NOT NULL CHECK (rendered_body <> ''),
    content_hash VARCHAR NOT NULL CHECK (content_hash <> ''),
    -- Which versioned ESIGN/UETA electronic-records disclosure the signer was
    -- shown and agreed to. The exact wording is reproducible from the code
    -- constant (Database/python_data/schema/esign_disclosure.py). The DB DEFAULT
    -- is a backward-compat backstop; the app always passes the value explicitly.
    esign_disclosure_version VARCHAR NOT NULL DEFAULT 'esign-v1'
        CHECK (esign_disclosure_version <> ''),
    -- The staff member who captured the in-person signature (witness /
    -- attribution). NULLABLE: legacy rows have no historical operator and the FK
    -- forbids a sentinel; both capture paths always supply it going forward.
    operator_employee_id UUID,
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
        REFERENCES gym_waiver_versions (version_id, gym_id),

    CONSTRAINT fk_waiver_sig_operator
        FOREIGN KEY (operator_employee_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);

CREATE INDEX idx_member_waiver_signatures_member
    ON member_waiver_signatures (member_id, gym_id);
CREATE INDEX idx_member_waiver_signatures_waiver
    ON member_waiver_signatures (waiver_id);
CREATE INDEX idx_member_waiver_signatures_version
    ON member_waiver_signatures (waiver_version_id);
CREATE INDEX idx_member_waiver_signatures_operator
    ON member_waiver_signatures (operator_employee_id, gym_id);
