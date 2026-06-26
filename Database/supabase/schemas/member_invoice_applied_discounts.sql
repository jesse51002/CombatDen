-- Per-invoice discount audit. One row = one Stripe coupon applied to ONE invoice
-- LINE, captured at invoice time by the invoice.paid webhook (which resolves the
-- coupon via a Stripe expand-retrieve, since the webhook payload carries only
-- opaque Discount ids). Capture is per line (line.discount_amounts), not the
-- invoice-level rollup, so a coupon SHARED across two family lines records one row
-- per line instead of collapsing into one. line_item_id is the Stripe invoice line
-- id (il_...); it is an audit value, not FK-enforced (like stripe_coupon_id),
-- since proration-credit lines are not persisted as line-item rows. amount_off is
-- the dollar value the coupon took off this line, snapshotted. The Stripe coupon
-- id is the identifier -- we deliberately do NOT resolve back to a CRM gym_discount
-- (the value-signature coupon is shared across discounts, so the link is
-- ambiguous); discount_id stays nullable for a possible future link.
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

    -- Idempotent on webhook re-delivery: one row per coupon per invoice LINE, so
    -- a coupon shared across sibling lines is recorded once for each line.
    CONSTRAINT uq_applied_discount_invoice_coupon_line
        UNIQUE (invoice_id, stripe_coupon_id, line_item_id),

    CONSTRAINT fk_applied_discount_invoice_gym
        FOREIGN KEY (invoice_id, gym_id)
        REFERENCES member_invoices (invoice_id, gym_id),

    -- Kept for a possible future CRM link; not enforced while discount_id is NULL
    -- (a composite FK with a NULL column is not checked).
    CONSTRAINT fk_applied_discount_discount_gym
        FOREIGN KEY (discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

CREATE INDEX idx_applied_discounts_invoice
    ON member_invoice_applied_discounts (invoice_id);
