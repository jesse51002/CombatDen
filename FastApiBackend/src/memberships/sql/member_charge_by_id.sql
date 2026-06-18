-- Fetch one member_charges row by its PK, scoped to the given member's gym,
-- with the per-charge already-refunded total (the sum of refund rows linked to
-- it). The gym match is the auth boundary: a caller can only reach a charge
-- that lives in the same gym as the member whose page the refund was launched
-- from — pairing a viewable member with another gym's charge id finds nothing.
SELECT
    c.charge_id,
    c.invoice_id,
    c.member_id AS charge_member_id,
    c.gym_id,
    c.kind,
    c.status,
    c.amount,
    c.currency,
    c.stripe_charge_id,
    c.payment_method_type,
    c.card_last_four,
    COALESCE((
        SELECT -SUM(r.amount)
        FROM member_charges r
        WHERE r.refunds_charge_id = c.charge_id
          AND r.kind = 'refund'
    ), 0) AS already_refunded
FROM member_charges c
WHERE c.charge_id = :charge_id
  AND c.gym_id = (
        SELECT m.gym_id FROM members m WHERE m.member_id = :member_id
      )
LIMIT 1
