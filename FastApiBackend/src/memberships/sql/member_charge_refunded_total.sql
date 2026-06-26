-- Sum the SUCCEEDED refunds already linked to a charge, returned as a positive
-- minor-units total (refund rows store a negative amount, so negate the SUM).
-- Run AFTER acquiring the parent-row lock (member_charge_lock.sql) so that, in a
-- fresh READ COMMITTED snapshot, it sees any refund a just-committed concurrent
-- request inserted -- the basis for the under-lock refundable re-check.
SELECT COALESCE((
    SELECT -SUM(r.amount)
    FROM member_charges r
    WHERE r.refunds_charge_id = :charge_id
      AND r.kind = 'refund'
      AND r.status = 'succeeded'
), 0) AS already_refunded
