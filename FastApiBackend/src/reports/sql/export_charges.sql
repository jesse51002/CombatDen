-- Raw charges (payments + refunds) for the gym. EXCLUDES stripe_event_payload.
-- Amounts are raw cents (payments >= 0, refunds <= 0).
SELECT
    c.charge_id,
    c.invoice_id,
    c.gym_id,
    c.paid_by_member_id,
    c.kind,
    c.status,
    c.amount,
    c.currency,
    c.payment_method_type,
    c.card_last_four,
    c.stripe_charge_id,
    c.stripe_refund_id,
    c.refunds_charge_id,
    c.charge_time
FROM member_charges c
WHERE c.gym_id = CAST(:gym_id AS UUID)
ORDER BY c.charge_time ASC, c.charge_id ASC
