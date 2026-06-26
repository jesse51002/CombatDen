-- Lock the parent charge row (SELECT ... FOR UPDATE) for the rest of the
-- transaction so concurrent refunds against the same charge serialize. A second
-- refund blocks here until the first commits, then re-reads the refunded total
-- (member_charge_refunded_total.sql, a separate statement under a fresh
-- snapshot) and re-checks the refundable balance before inserting. This row
-- lock is the ONLY guard for cash refunds: a cash refund row carries a NULL
-- stripe_refund_id, so the UNIQUE(stripe_refund_id) constraint never fires to
-- stop two concurrent full cash refunds. Returns the charge's gross amount.
SELECT c.amount
FROM member_charges c
WHERE c.charge_id = :charge_id
FOR UPDATE
