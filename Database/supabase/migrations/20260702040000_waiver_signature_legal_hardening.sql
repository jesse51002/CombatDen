-- Hand-authored migration.
-- Legal-hardening pass for the waiver e-signature system, covering four changes:
--
--   1. gym_waiver_versions.requires_resign (BOOLEAN NOT NULL DEFAULT true) — a
--      per-version re-sign gate flag. When a body edit forks a new version, the
--      backend sets this field: true = material change, prior signers must re-sign
--      before their next purchase; false = minor edit (typo) that does NOT
--      invalidate prior signatures. The compliance floor is the highest
--      version_number with requires_resign = true. Backfilled true so all existing
--      versions are treated as material.
--
--   2. member_waiver_signatures.ip_address + user_agent made NOT NULL — the capture
--      paths always supply these audit fields; any legacy NULLs are backfilled to
--      sentinels ('0.0.0.0' / 'backfilled-unknown') before the NOT NULL constraint
--      is applied so the migration is non-destructive.
--
--   3. member_waiver_signatures.esign_disclosure_version (VARCHAR NOT NULL) — pins
--      which versioned ESIGN/UETA electronic-records disclosure the signer was
--      shown. The DEFAULT 'esign-v1' is a backward-compat backstop; the app always
--      passes the value explicitly. An empty-string CHECK guards against silent
--      blank values.
--
--   4. member_waiver_signatures.operator_employee_id (UUID NULLABLE) — the staff
--      member (witness/operator) who captured an in-person signature. Composite FK
--      to gym_employees(employee_id, gym_id); NULLABLE because legacy rows have no
--      historical operator and the FK forbids a sentinel. An index covers the FK
--      columns for lookup efficiency.
--
--   5. member_waiver_signatures.rendered_body (TEXT NOT NULL) — the EXACT text the
--      signer agreed to: the version template with its {{placeholders}} filled in.
--      content_hash becomes the sha256 of this rendered text. Legacy rows are
--      backfilled from their template version's body (no placeholders historically)
--      before the NOT NULL is applied.

-- ── 1. gym_waiver_versions: add requires_resign ────────────────────────────────

ALTER TABLE gym_waiver_versions
    ADD COLUMN requires_resign BOOLEAN NOT NULL DEFAULT true;

-- ── 2. member_waiver_signatures: NOT-NULL audit fields ────────────────────────

-- Backfill legacy NULLs to sentinels before applying NOT NULL constraints.
-- CAST(... AS INET) avoids the banned ::type cast syntax.
UPDATE member_waiver_signatures
    SET ip_address = CAST('0.0.0.0' AS INET)
    WHERE ip_address IS NULL;

UPDATE member_waiver_signatures
    SET user_agent = 'backfilled-unknown'
    WHERE user_agent IS NULL;

ALTER TABLE member_waiver_signatures ALTER COLUMN ip_address SET NOT NULL;
ALTER TABLE member_waiver_signatures ALTER COLUMN user_agent SET NOT NULL;

-- ── 3. member_waiver_signatures: ESIGN disclosure version ─────────────────────

ALTER TABLE member_waiver_signatures
    ADD COLUMN esign_disclosure_version VARCHAR NOT NULL DEFAULT 'esign-v1'
    CONSTRAINT chk_waiver_sig_esign_version CHECK (esign_disclosure_version <> '');

-- ── 4. member_waiver_signatures: operator/witness column ──────────────────────

ALTER TABLE member_waiver_signatures ADD COLUMN operator_employee_id UUID;

ALTER TABLE member_waiver_signatures
    ADD CONSTRAINT fk_waiver_sig_operator
    FOREIGN KEY (operator_employee_id, gym_id)
    REFERENCES gym_employees (employee_id, gym_id);

CREATE INDEX idx_member_waiver_signatures_operator
    ON member_waiver_signatures (operator_employee_id, gym_id);

-- ── 5. member_waiver_signatures: rendered_body (the exact agreed text) ─────────

-- Backfill legacy rows from their template version's body (no placeholders were
-- used historically), then apply NOT NULL + non-empty CHECK.
ALTER TABLE member_waiver_signatures ADD COLUMN rendered_body TEXT;

UPDATE member_waiver_signatures s
    SET rendered_body = v.body
    FROM gym_waiver_versions v
    WHERE v.version_id = s.waiver_version_id
      AND s.rendered_body IS NULL;

ALTER TABLE member_waiver_signatures ALTER COLUMN rendered_body SET NOT NULL;
ALTER TABLE member_waiver_signatures
    ADD CONSTRAINT chk_waiver_sig_rendered_body CHECK (rendered_body <> '');
