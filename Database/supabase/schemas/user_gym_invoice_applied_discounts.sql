-- Discounts applied to an invoice. Real FK to gym_discounts_unfiltered so we
-- can't attach a discount that doesn't belong to the invoice's gym. amount_off
-- is a snapshot of the dollar value applied at invoice time -- the underlying
-- discount's percentage/dollar_off may change later.
CREATE TABLE user_gym_invoice_applied_discounts (
    applied_discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL
        CONSTRAINT fk_applied_discount_invoice
        REFERENCES user_gym_invoices(invoice_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL
        CONSTRAINT fk_applied_discount_gym REFERENCES gyms_unfiltered(gym_id),
    discount_id UUID NOT NULL,
    amount_off INTEGER NOT NULL CHECK (amount_off >= 0),
    stripe_coupon_id VARCHAR,

    PRIMARY KEY (applied_discount_id),

    CONSTRAINT fk_applied_discount_invoice_gym
        FOREIGN KEY (invoice_id, gym_id)
        REFERENCES user_gym_invoices (invoice_id, gym_id),

    CONSTRAINT fk_applied_discount_discount_gym
        FOREIGN KEY (discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

CREATE INDEX idx_applied_discounts_invoice
    ON user_gym_invoice_applied_discounts (invoice_id);
