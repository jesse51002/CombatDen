INSERT INTO member_invoices (
    gym_id,
    paid_by_member_id,
    paid_for,
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
    :paid_by_member_id,
    CAST(:paid_for AS JSONB),
    CAST(:status AS invoice_status),
    :total_amount,
    :currency,
    :stripe_invoice_id,
    :stripe_payment_intent_id,
    :invoice_time,
    CAST(:stripe_event_payload AS JSONB)
)
-- paid_by_member_id / paid_for are set once on first insert (the first
-- writer resolves them) and intentionally NOT updated on conflict, mirroring
-- how member_id used to be insert-only.
ON CONFLICT (stripe_invoice_id) DO UPDATE
SET status = EXCLUDED.status,
    total_amount = EXCLUDED.total_amount,
    currency = EXCLUDED.currency,
    stripe_payment_intent_id = EXCLUDED.stripe_payment_intent_id,
    invoice_time = EXCLUDED.invoice_time,
    stripe_event_payload = EXCLUDED.stripe_event_payload
RETURNING invoice_id,
          paid_by_member_id
