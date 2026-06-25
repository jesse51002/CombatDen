-- Fast-fail pre-check: does payer_member_id authorize-to-pay for member_id?
-- One row iff the authorization exists. Run BEFORE the cascading de-authorize
-- so a missing authorization is rejected up-front, before any Stripe cancel —
-- the delete itself also RETURNs the row, but that fires only after the cancels
-- have already committed.
SELECT 1
FROM member_authorized_payers
WHERE member_id = :member_id
  AND payer_member_id = :payer_member_id
