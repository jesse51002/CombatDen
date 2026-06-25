-- Insert an authorization: payer_member_id may pay for member_id, gated by the
-- signed waiver (signature_id). Runs in the CALLER's transaction (the link flow
-- records the signature + this row atomically), so no commit here. The PK
-- (member_id, payer_member_id) rejects a duplicate authorization.
INSERT INTO member_authorized_payers (
    member_id,
    payer_member_id,
    gym_id,
    signature_id
)
VALUES (
    :member_id,
    :payer_member_id,
    :gym_id,
    :signature_id
)
RETURNING member_id
