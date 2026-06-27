-- Per-invoice discount audit: one row per Stripe coupon per invoice line.
-- Coupon resolved via Stripe expand-retrieve (webhook payload carries only di_ ids).
-- stripe_coupon_id is the identifier; discount_id is nullable for a possible future CRM link.
CREATE TABLE member_invoice_applied_discounts (
    applied_discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL
        CONSTRAINT fk_applied_discount_invoice
        REFERENCES member_invoices(invoice_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL
        CONSTRAINT fk_applied_discount_gym REFERENCES gyms(gym_id),
    discount_id UUID,
    line_item_id VARCHAR NOT NULL,
    amount_off INTEGER NOT NULL CHECK (amount_off >= 0),
    stripe_coupon_id VARCHAR NOT NULL,

    PRIMARY KEY (applied_discount_id),

    CONSTRAINT uq_applied_discount_invoice_coupon_line
        UNIQUE (invoice_id, stripe_coupon_id, line_item_id),

    CONSTRAINT fk_applied_discount_invoice_gym
        FOREIGN KEY (invoice_id, gym_id)
        REFERENCES member_invoices (invoice_id, gym_id),

    -- Not enforced while discount_id is NULL (composite FK with a NULL column is not checked).
    CONSTRAINT fk_applied_discount_discount_gym
        FOREIGN KEY (discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

CREATE INDEX idx_applied_discounts_invoice
    ON member_invoice_applied_discounts (invoice_id);
