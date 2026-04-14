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
    i.total_amount AS invoice_total,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'line_item_id', li.line_item_id,
            'item_type', li.item_type,
            'name', li.name,
            'amount', li.amount,
            'stripe_product_id', li.stripe_product_id,
            'item_id', li.item_id
         ) ORDER BY li.line_item_id)
         FROM user_gym_invoice_line_items li
         WHERE li.invoice_id = i.invoice_id),
        '[]'::jsonb
    ) AS line_items,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'discount_id', ad.discount_id,
            'amount_off', ad.amount_off
         ))
         FROM user_gym_invoice_applied_discounts ad
         WHERE ad.invoice_id = i.invoice_id),
        '[]'::jsonb
    ) AS applied_discounts
FROM user_gym_charges c
JOIN user_gym_invoices i ON i.invoice_id = c.invoice_id
WHERE c.gym_id = :gym_id
    AND c.crm_user_id = :crm_user_id
ORDER BY c.charge_time DESC
