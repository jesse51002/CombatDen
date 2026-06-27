-- Fetch one member_charges row by its PK, scoped to the given member's gym,
-- with the per-charge already-refunded total (the sum of refund rows linked to
-- it). The gym match is the auth boundary: a caller can only reach a charge
-- that lives in the same gym as the member whose page the refund was launched
-- from — pairing a viewable member with another gym's charge id finds nothing.
SELECT
    c.charge_id,
    c.invoice_id,
    c.paid_by_member_id AS charge_paid_by_member_id,
    c.gym_id,
    c.kind,
    c.status,
    c.amount,
    c.currency,
    c.stripe_charge_id,
    c.payment_method_type,
    c.card_last_four,
    -- Only SUCCEEDED refunds reduce the refundable balance. Today every refund
    -- row is written succeeded (the service and the webhook never write a
    -- pending/failed refund), so this guard is a no-op now — it makes the
    -- invariant explicit so a future failed/cancelled refund row can't silently
    -- undercount the balance.
    COALESCE((
        SELECT -SUM(r.amount)
        FROM member_charges r
        WHERE r.refunds_charge_id = c.charge_id
          AND r.kind = 'refund'
          AND r.status = 'succeeded'
    ), 0) AS already_refunded
FROM member_charges c
WHERE c.charge_id = :charge_id
  AND c.gym_id = (
        SELECT m.gym_id FROM members m WHERE m.member_id = :member_id
      )
LIMIT 1
