-- Record an e-signature against a specific waiver version (append-only).
-- member_id is the SIGNER (for an authorized-payer waiver, the payer X). The
-- caller passes the version's content_hash so the exact signed text is frozen
-- onto the row. Runs in the CALLER's transaction (the link flow records this +
-- the member_authorized_payers row atomically), so no commit here.
INSERT INTO member_waiver_signatures (
    gym_id,
    member_id,
    waiver_id,
    waiver_version_id,
    signer_name,
    consent_acknowledged,
    rendered_body,
    content_hash,
    ip_address,
    user_agent,
    esign_disclosure_version,
    operator_employee_id
)
VALUES (
    :gym_id,
    :signer_member_id,
    :waiver_id,
    :waiver_version_id,
    :signer_name,
    :consent_acknowledged,
    :rendered_body,
    :content_hash,
    :ip_address,
    :user_agent,
    :esign_disclosure_version,
    :operator_employee_id
)
RETURNING signature_id, signed_at, signature_type
