-- Raw waiver e-signature audit records for the gym -- the full legal evidence,
-- INCLUDING the exact rendered_body the signer agreed to and its content_hash
-- (the whole point of a signature export). ip_address is rendered as its text
-- form.
SELECT
    sig.signature_id,
    sig.gym_id,
    sig.member_id,
    sig.waiver_id,
    sig.waiver_version_id,
    sig.signed_at,
    sig.signer_name,
    sig.signature_type,
    sig.consent_acknowledged,
    CAST(sig.ip_address AS TEXT) AS ip_address,
    sig.user_agent,
    sig.rendered_body,
    sig.content_hash,
    sig.esign_disclosure_version,
    sig.operator_employee_id
FROM member_waiver_signatures sig
WHERE sig.gym_id = CAST(:gym_id AS UUID)
ORDER BY sig.signed_at ASC, sig.signature_id ASC
