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
    stripe_charge_id,
    stripe_refund_id,
    refunds_charge_id,
    charge_time,
    stripe_event_payload
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
    :stripe_charge_id,
    :stripe_refund_id,
    :refunds_charge_id,
    :charge_time,
    CAST(:stripe_event_payload AS JSONB)
)
ON CONFLICT DO NOTHING
RETURNING charge_id
