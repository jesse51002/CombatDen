-- Raw invoices for the gym. EXCLUDES stripe_event_payload (the raw Stripe
-- event blob is internal). paid_for is a JSONB array rendered as its text form.
SELECT
    i.invoice_id,
    i.gym_id,
    i.paid_by_member_id,
    CAST(i.paid_for AS TEXT) AS paid_for,
    i.status,
    i.total_amount,
    i.currency,
    i.stripe_invoice_id,
    i.stripe_payment_intent_id,
    i.invoice_time
FROM member_invoices i
WHERE i.gym_id = CAST(:gym_id AS UUID)
ORDER BY i.invoice_time ASC, i.invoice_id ASC
