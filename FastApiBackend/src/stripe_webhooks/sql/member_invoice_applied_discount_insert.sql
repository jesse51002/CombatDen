INSERT INTO member_invoice_applied_discounts (
    invoice_id,
    gym_id,
    line_item_id,
    amount_off,
    stripe_coupon_id
)
VALUES (
    :invoice_id,
    :gym_id,
    :line_item_id,
    :amount_off,
    :stripe_coupon_id
)
ON CONFLICT (invoice_id, stripe_coupon_id, line_item_id) DO NOTHING
