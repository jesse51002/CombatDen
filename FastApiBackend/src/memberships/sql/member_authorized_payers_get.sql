-- Is payer_member_id authorized to pay for member_id? Returns one row if so.
-- Used by _assert_payer_allowed and the link pre-check.
SELECT 1
FROM member_authorized_payers
WHERE member_id = :member_id
  AND payer_member_id = :payer_member_id
