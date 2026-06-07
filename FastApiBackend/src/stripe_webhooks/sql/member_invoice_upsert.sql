INSERT INTO member_invoices (
    gym_id,
    member_id,
    status,
    total_amount,
    currency,
    stripe_invoice_id,
    stripe_payment_intent_id,
    invoice_time,
    stripe_event_payload
)
VALUES (
    :gym_id,
    :member_id,
    CAST(:status AS invoice_status),
    :total_amount,
    :currency,
    :stripe_invoice_id,
    :stripe_payment_intent_id,
    :invoice_time,
    CAST(:stripe_event_payload AS JSONB)
)
ON CONFLICT (stripe_invoice_id) DO UPDATE
SET status = EXCLUDED.status,
    total_amount = EXCLUDED.total_amount,
    currency = EXCLUDED.currency,
    stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
    invoice_time = EXCLUDED.invoice_time,
    stripe_event_payload = EXCLUDED.stripe_event_payload
RETURNING invoice_id,
          member_id
