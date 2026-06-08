-- Paginated payment history for the member-detail screen.
--
-- Returns every charge that is this member's "stuff", by two paths:
--   1. charges the member actually PAID (c.member_id = :member_id) — even for
--      something they no longer / never held as a membership (ad-hoc charges,
--      a since-cancelled plan, paying for someone else's membership); and
--   2. charges for a MEMBERSHIP the member has ever held — any invoice line
--      item whose item_id is one of the member's member_memberships item_ids
--      (so a parent's payment for THIS member's membership shows here, and
--      pre-link membership invoices stay findable after they're linked).
-- A paying parent's UNRELATED charges never leak onto this member's page —
-- only the ones they paid OR the ones covering this member's memberships.
--
-- Only PAYMENT charges are returned as rows; a charge's refunds are folded in
-- as ``refunded_amount`` (the summed refund total against it), never separate
-- rows — so the history shows one line per payment and makes clear how much of
-- it was refunded. Each row carries who was actually charged (paid_by_*).
-- Newest first, windowed by :limit / :offset. The gym is derived from the
-- member, so the only inputs are :member_id, :limit, :offset.
WITH ctx AS (
    SELECT mbp.gym_id
    FROM member_billing_profile mbp
    WHERE mbp.member_id = :member_id
),
member_items AS (
    SELECT mm.item_id
    FROM member_memberships mm
    WHERE mm.member_id = :member_id
)
SELECT
    c.charge_id,
    c.invoice_id,
    c.kind,
    c.status,
    c.amount,
    c.currency,
    c.payment_method_type,
    c.charge_time,
    c.refunds_charge_id,
    COALESCE(
        (SELECT -SUM(r.amount)
         FROM member_charges r
         WHERE r.refunds_charge_id = c.charge_id),
        0
    ) AS refunded_amount,
    c.member_id AS paid_by_member_id,
    pm.first_name AS paid_by_first_name,
    pm.last_name AS paid_by_last_name,
    pmbp.photo_url AS paid_by_photo_url,
    i.total_amount AS invoice_total,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'line_item_id', li.line_item_id,
            'item_type', li.item_type,
            'name', li.name,
            'amount', li.amount,
            'quantity', li.quantity,
            'stripe_product_id', li.stripe_product_id,
            'item_id', li.item_id
         ) ORDER BY li.line_item_id)
         FROM member_invoice_line_items li
         WHERE li.invoice_id = i.invoice_id),
        '[]'::jsonb
    ) AS line_items,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'stripe_coupon_id', ad.stripe_coupon_id,
            'amount_off', ad.amount_off
         ) ORDER BY ad.amount_off DESC)
         FROM member_invoice_applied_discounts ad
         WHERE ad.invoice_id = i.invoice_id),
        '[]'::jsonb
    ) AS applied_discounts,
    -- Every charge against this invoice (each retry + the success + any
    -- refunds), so the invoice popup can show the full attempt history.
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'charge_id', ac.charge_id,
            'kind', ac.kind,
            'status', ac.status,
            'amount', ac.amount,
            'payment_method_type', ac.payment_method_type,
            'card_last_four', ac.card_last_four,
            'charge_time', ac.charge_time
         ) ORDER BY ac.charge_time, ac.charge_id)
         FROM member_charges ac
         WHERE ac.invoice_id = i.invoice_id),
        '[]'::jsonb
    ) AS attempts
FROM member_charges c
JOIN member_invoices i ON i.invoice_id = c.invoice_id
CROSS JOIN ctx
LEFT JOIN members pm
    ON pm.member_id = c.member_id AND pm.gym_id = c.gym_id
LEFT JOIN member_billing_profile pmbp
    ON pmbp.member_id = c.member_id AND pmbp.gym_id = c.gym_id
WHERE c.gym_id = ctx.gym_id
  AND c.kind = 'payment'
  AND (
      c.member_id = :member_id
      OR EXISTS (
          SELECT 1
          FROM member_invoice_line_items li
          WHERE li.invoice_id = i.invoice_id
            AND li.item_id IN (SELECT item_id FROM member_items)
      )
  )
ORDER BY c.charge_time DESC, c.charge_id
LIMIT :limit OFFSET :offset
