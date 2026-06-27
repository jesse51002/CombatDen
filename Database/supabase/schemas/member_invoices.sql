-- An invoice is the bill. One row per Stripe invoice (or manually-created
-- invoice for cash). Children: line items, charges, applied discounts.
-- Void / uncollectible invoices are not stored -- the webhook deletes the row
-- and ON DELETE CASCADE cleans up the children.
--
-- Payer vs. beneficiaries are tracked separately: paid_by_member_id is the one
-- member whose Stripe customer/card was billed; paid_for is the JSONB list of
-- the member_ids this bill was FOR (usually just [payer]; a parent paying for a
-- child lists the child; a consolidated family invoice lists every owner). A
-- payment thus surfaces on the payer's page (paid_by_member_id) AND every
-- beneficiary's page (paid_for).
CREATE TYPE invoice_status AS ENUM ('open', 'paid');

CREATE TABLE member_invoices (
    invoice_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_invoice_gym REFERENCES gyms(gym_id),

    -- The payer: whose Stripe customer/card was billed (cash: whoever staff
    -- recorded as paying).
    paid_by_member_id UUID NOT NULL,
    -- The beneficiaries the bill was FOR: a JSONB array of member_id strings.
    paid_for JSONB NOT NULL DEFAULT '[]',

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

    CONSTRAINT fk_invoice_payer_gym
        FOREIGN KEY (paid_by_member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_invoices_payer_gym_time
    ON member_invoices (paid_by_member_id, gym_id, invoice_time DESC);

CREATE INDEX idx_invoices_gym_time
    ON member_invoices (gym_id, invoice_time DESC);

-- Beneficiary lookup: "every invoice this member was paid FOR" (the
-- payment-history beneficiary arm + the member-sees-own RLS containment).
CREATE INDEX idx_invoices_paid_for
    ON member_invoices USING GIN (paid_for);
