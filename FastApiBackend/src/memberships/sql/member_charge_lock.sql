-- Lock the parent charge row for the transaction (serializes concurrent refunds).
-- Critical for cash refunds: NULL stripe_refund_id means UNIQUE constraint won't fire.
SELECT c.amount
FROM member_charges c
WHERE c.charge_id = :charge_id
FOR UPDATE
