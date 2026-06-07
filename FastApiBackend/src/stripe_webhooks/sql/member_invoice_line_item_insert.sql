-- Persist one Stripe invoice line. PK is the Stripe line id, so a redelivered
-- invoice.paid is idempotent (ON CONFLICT DO NOTHING).
INSERT INTO member_invoice_line_items (
    line_item_id,
    invoice_id,
    gym_id,
    item_type,
    name,
    amount,
    quantity,
    stripe_product_id,
    item_id
)
VALUES (
    :line_item_id,
    CAST(:invoice_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:item_type AS line_item_type),
    :name,
    :amount,
    :quantity,
    :stripe_product_id,
    CAST(:item_id AS UUID)
)
ON CONFLICT (line_item_id) DO NOTHING
