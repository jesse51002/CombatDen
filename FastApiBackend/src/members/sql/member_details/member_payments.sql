-- Paginated payment history for the member-detail screen.
--
-- Returns one row per INVOICE that is this member's "stuff", by three paths:
--   1. an invoice the member PAID (c.paid_by_member_id = :member_id) — even for
--      something they no longer / never held as a membership (ad-hoc charges, a
--      since-cancelled plan, paying for someone else); and
--   2. an invoice for a MEMBERSHIP the member has ever held — any line item
--      whose item_id is one of the member's member_memberships item_ids (so a
--      parent's payment for THIS member's membership shows here, and pre-link
--      membership invoices stay findable after they're linked); and
--   3. an invoice that was FOR the member — their id is in the invoice's
--      paid_for beneficiary list (a parent paying for this member shows here,
--      so the charge is findable + refundable from this member's page).
-- A paying parent's UNRELATED invoices never leak onto this member's page.
-- The row's payer label is the invoice's paid_by_member_id; "For …" is paid_for.
--
-- ONE row per invoice: every charge against the invoice (each retry, the
-- success, and any refunds — there can be several payments, e.g. a refund then
-- a re-charge) is folded into that single row. The row carries the invoice
-- TOTAL (amount), how much of it was REFUNDED (refunded_amount = summed refund
-- total on the invoice), and every charge under ``attempts``; a representative
-- payment charge (a succeeded one if any, else the most recent) owns the row's
-- status / time / payer / charge_id (the latter is what the refund action
-- targets). Newest first, windowed by :limit / :offset. The gym is derived
-- from the member, so the only inputs are :member_id, :limit, :offset.
WITH ctx AS (
    SELECT mbp.gym_id
    FROM member_billing_profile mbp
    WHERE mbp.member_id = :member_id
),
member_items AS (
    SELECT mm.item_id
    FROM member_memberships mm
    WHERE mm.member_id = :member_id
),
-- The invoices that are this member's "stuff" (a payment they made, or a line
-- item for a membership they have ever held).
relevant_invoices AS (
    SELECT DISTINCT c.invoice_id
    FROM member_charges c
    CROSS JOIN ctx
    WHERE c.gym_id = ctx.gym_id
      AND c.kind = 'payment'
      AND (
          -- I paid for it.
          c.paid_by_member_id = :member_id
          -- A membership I have ever held was on it (keeps pre-link /
          -- historical invoices findable independent of the paid_for snapshot).
          OR EXISTS (
              SELECT 1
              FROM member_invoice_line_items li
              WHERE li.invoice_id = c.invoice_id
                AND li.item_id IN (SELECT item_id FROM member_items)
          )
          -- The bill was FOR me (my id is in the invoice's paid_for list).
          OR EXISTS (
              SELECT 1
              FROM member_invoices inv
              WHERE inv.invoice_id = c.invoice_id
                AND jsonb_exists(inv.paid_for, :member_id_text)
          )
      )
),
-- One representative payment charge per invoice: a succeeded one if any, then
-- the most recent. It owns the row's status / time / payer / charge_id; all
-- charges still appear under ``attempts``.
rep_charge AS (
    SELECT DISTINCT ON (c.invoice_id)
        c.invoice_id,
        c.charge_id,
        c.status,
        c.amount,
        c.currency,
        c.payment_method_type,
        c.charge_time,
        c.paid_by_member_id,
        c.gym_id
    FROM member_charges c
    WHERE c.invoice_id IN (SELECT invoice_id FROM relevant_invoices)
      AND c.kind = 'payment'
    ORDER BY
        c.invoice_id,
        (c.status = 'succeeded') DESC,
        c.charge_time DESC,
        c.charge_id
)
SELECT
    rc.charge_id,
    rc.invoice_id,
    'payment' AS kind,
    rc.status,
    rc.amount,
    rc.currency,
    rc.payment_method_type,
    rc.charge_time,
    NULL AS refunds_charge_id,
    -- Summed refund total against the whole invoice (refund amounts are stored
    -- negative), so a re-charge does not split the refund across rows.
    COALESCE(
        (SELECT -SUM(r.amount)
         FROM member_charges r
         WHERE r.invoice_id = rc.invoice_id
           AND r.kind = 'refund'),
        0
    ) AS refunded_amount,
    rc.paid_by_member_id AS paid_by_member_id,
    pm.first_name AS paid_by_first_name,
    pm.last_name AS paid_by_last_name,
    pmbp.photo_url AS paid_by_photo_url,
    -- Beneficiaries: who the bill was FOR (the invoice's paid_for, resolved to
    -- names) so the row can show "For X, Y". Usually just the payer themselves.
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'member_id', bm.member_id,
            'first_name', bm.first_name,
            'last_name', bm.last_name,
            'photo_url', bm.photo_url
         ) ORDER BY bm.first_name, bm.last_name)
         FROM member_invoices inv2
         CROSS JOIN LATERAL
             jsonb_array_elements_text(inv2.paid_for) AS pf(mid)
         JOIN members bm
             ON bm.member_id = CAST(pf.mid AS UUID)
            AND bm.gym_id = rc.gym_id
         WHERE inv2.invoice_id = rc.invoice_id),
        '[]'::jsonb
    ) AS paid_for,
    -- Each line's owner(s) — the member(s) the line is FOR, comma-joined.
    -- A membership line can be a CONSOLIDATED item (quantity > 1) shared by
    -- several co-owners at one price, so resolve the line's membership ->
    -- its Stripe item -> EVERY membership on that item -> their members (not
    -- just one). A custom/ad-hoc line has no item_id, so owner_label is NULL.
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'line_item_id', li.line_item_id,
            'item_type', li.item_type,
            'name', li.name,
            'amount', li.amount,
            'quantity', li.quantity,
            'stripe_product_id', li.stripe_product_id,
            'item_id', li.item_id,
            'owner_label', (
                SELECT string_agg(
                    DISTINCT om.first_name || ' ' || om.last_name, ', ')
                FROM member_memberships_unfiltered lm
                JOIN member_memberships_unfiltered sib
                    ON sib.stripe_item_id = lm.stripe_item_id
                   AND sib.gym_id = rc.gym_id
                JOIN members om
                    ON om.member_id = sib.member_id
                   AND om.gym_id = rc.gym_id
                WHERE lm.item_id = li.item_id
                  AND lm.gym_id = rc.gym_id
            )
         ) ORDER BY li.line_item_id)
         FROM member_invoice_line_items li
         WHERE li.invoice_id = rc.invoice_id),
        '[]'::jsonb
    ) AS line_items,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'stripe_coupon_id', ad.stripe_coupon_id,
            'amount_off', ad.amount_off
         ) ORDER BY ad.amount_off DESC)
         FROM member_invoice_applied_discounts ad
         WHERE ad.invoice_id = rc.invoice_id),
        '[]'::jsonb
    ) AS applied_discounts,
    -- Every charge against this invoice (each retry + the success + any
    -- refunds), so the invoice popup shows the full attempt history.
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
         WHERE ac.invoice_id = rc.invoice_id),
        '[]'::jsonb
    ) AS attempts
FROM rep_charge rc
LEFT JOIN members pm
    ON pm.member_id = rc.paid_by_member_id AND pm.gym_id = rc.gym_id
LEFT JOIN member_billing_profile pmbp
    ON pmbp.member_id = rc.paid_by_member_id AND pmbp.gym_id = rc.gym_id
ORDER BY rc.charge_time DESC, rc.charge_id
LIMIT :limit OFFSET :offset
