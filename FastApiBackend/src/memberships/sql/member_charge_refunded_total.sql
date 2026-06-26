-- Sum succeeded refunds on a charge as a positive total (rows store negative amounts).
-- Run after the parent-row lock so a fresh snapshot includes concurrent commits.
SELECT COALESCE((
    SELECT -SUM(r.amount)
    FROM member_charges r
    WHERE r.refunds_charge_id = :charge_id
      AND r.kind = 'refund'
      AND r.status = 'succeeded'
), 0) AS already_refunded
