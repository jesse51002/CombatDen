-- Raw invoice line items for the gym. No timestamp of their own, so ordered by
-- the parent invoice id then the line item id.
SELECT
    li.line_item_id,
    li.invoice_id,
    li.gym_id,
    li.item_type,
    li.name,
    li.amount,
    li.quantity,
    li.stripe_product_id,
    li.item_id
FROM member_invoice_line_items li
WHERE li.gym_id = CAST(:gym_id AS UUID)
ORDER BY li.invoice_id ASC, li.line_item_id ASC
