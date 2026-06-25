-- Remove an authorization. RETURNING lets the caller detect "was not linked".
-- The signature row in member_waiver_signatures is append-only and persists as
-- the audit trail.
DELETE FROM member_authorized_payers
WHERE member_id = :member_id
  AND payer_member_id = :payer_member_id
RETURNING member_id
