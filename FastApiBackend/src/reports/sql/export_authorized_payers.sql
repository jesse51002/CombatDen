-- Raw authorized-payer links for the gym (who may pay for whom + the signature
-- that gated the link). Composite PK, so ordered by created_at then both ids.
SELECT
    ap.member_id,
    ap.payer_member_id,
    ap.gym_id,
    ap.signature_id,
    ap.created_at
FROM member_authorized_payers ap
WHERE ap.gym_id = CAST(:gym_id AS UUID)
ORDER BY ap.created_at ASC, ap.member_id ASC, ap.payer_member_id ASC
