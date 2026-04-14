INSERT INTO user_gym_charges (
    invoice_id,
    gym_id,
    crm_user_id,
    kind,
    status,
    amount,
    currency,
    payment_method_type,
    stripe_charge_id,
    stripe_refund_id,
    refunds_charge_id,
    charge_time,
    stripe_event_payload
)
VALUES (
    :invoice_id,
    :gym_id,
    :crm_user_id,
    CAST(:kind AS charge_kind),
    CAST(:status AS charge_status),
    :amount,
    :currency,
    :payment_method_type,
    :stripe_charge_id,
    :stripe_refund_id,
    :refunds_charge_id,
    :charge_time,
    CAST(:stripe_event_payload AS JSONB)
)
ON CONFLICT DO NOTHING
RETURNING charge_id
