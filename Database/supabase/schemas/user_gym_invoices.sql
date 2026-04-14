-- An invoice is the bill. One row per Stripe invoice (or manually-created
-- invoice for cash). Children: line items, charges, applied discounts.
-- Void / uncollectible invoices are not stored -- the webhook deletes the row
-- and ON DELETE CASCADE cleans up the children.
CREATE TYPE invoice_status AS ENUM ('open', 'paid');

CREATE TABLE user_gym_invoices (
    invoice_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_invoice_gym REFERENCES gyms(gym_id),
    crm_user_id UUID NOT NULL,

    status invoice_status NOT NULL DEFAULT 'open',
    total_amount INTEGER NOT NULL CHECK (total_amount >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'usd',

    -- Nullable because a manually-created invoice (e.g. cash) won't have them.
    stripe_invoice_id VARCHAR UNIQUE,
    stripe_payment_intent_id VARCHAR UNIQUE,

    invoice_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    stripe_event_payload JSONB,

    PRIMARY KEY (invoice_id),
    -- Composite FK target for child tables that denormalize gym_id
    UNIQUE (invoice_id, gym_id),

    CONSTRAINT fk_invoice_user_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id)
);

CREATE INDEX idx_invoices_user_gym_time
    ON user_gym_invoices (crm_user_id, gym_id, invoice_time DESC);

CREATE INDEX idx_invoices_gym_time
    ON user_gym_invoices (gym_id, invoice_time DESC);
