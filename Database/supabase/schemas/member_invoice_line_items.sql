-- What's on the bill. PK is the Stripe line item id directly (il_xxx) -- line
-- items always originate from Stripe, so reusing the Stripe id gives free
-- idempotency with no mapping layer.
CREATE TYPE line_item_type AS ENUM ('membership', 'custom');

CREATE TABLE member_invoice_line_items (
    line_item_id VARCHAR NOT NULL,  -- = Stripe line item id (il_xxx)
    invoice_id UUID NOT NULL
        CONSTRAINT fk_line_item_invoice
        REFERENCES member_invoices(invoice_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL CONSTRAINT fk_line_item_gym REFERENCES gyms(gym_id),

    item_type line_item_type NOT NULL,
    name VARCHAR NOT NULL CHECK (name <> ''),  -- frozen historical label
    amount INTEGER NOT NULL CHECK (amount >= 0),  -- line total (post-qty)
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),

    -- Stripe-side trace. Nullable for cash / non-Stripe lines.
    stripe_product_id VARCHAR,

    -- Only set when item_type = 'membership'
    item_id UUID,

    PRIMARY KEY (line_item_id),

    CONSTRAINT fk_line_item_invoice_gym
        FOREIGN KEY (invoice_id, gym_id)
        REFERENCES member_invoices (invoice_id, gym_id),

    CONSTRAINT fk_line_item_membership_gym
        FOREIGN KEY (item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),

    CONSTRAINT membership_line_has_item_id
        CHECK (item_type <> 'membership' OR item_id IS NOT NULL),
    CONSTRAINT custom_line_has_no_item_id
        CHECK (item_type <> 'custom' OR item_id IS NULL)
);

CREATE INDEX idx_line_items_invoice
    ON member_invoice_line_items (invoice_id);

CREATE INDEX idx_line_items_item
    ON member_invoice_line_items (item_id)
    WHERE item_id IS NOT NULL;
