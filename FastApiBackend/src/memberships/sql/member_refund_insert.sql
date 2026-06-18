-- Record an endpoint-initiated refund as a negative member_charges row.
-- Serves both branches: a card refund carries its stripe_refund_id, a cash
-- refund leaves it NULL (no Stripe object). Idempotent on stripe_refund_id, so
-- a later refund.* webhook for the same card refund is a harmless no-op. A cash
-- refund has a NULL stripe_refund_id (NULLs never conflict), so it always
-- inserts. No stripe_charge_id (refunds never carry one) and no event payload
-- (there is no inbound Stripe event for an endpoint-initiated refund).
INSERT INTO member_charges (
    invoice_id,
    gym_id,
    member_id,
    kind,
    status,
    amount,
    currency,
    payment_method_type,
    card_last_four,
    stripe_refund_id,
    refunds_charge_id,
    charge_time
)
VALUES (
    :invoice_id,
    :gym_id,
    :member_id,
    CAST(:kind AS charge_kind),
    CAST(:status AS charge_status),
    :amount,
    :currency,
    :payment_method_type,
    :card_last_four,
    :stripe_refund_id,
    :refunds_charge_id,
    :charge_time
)
ON CONFLICT DO NOTHING
RETURNING charge_id
