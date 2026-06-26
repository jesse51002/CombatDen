-- Money movement. Payments and refunds both live here.
--   kind='payment':  amount >= 0, stripe_charge_id set (or cash), no parent
--   kind='refund':   amount <= 0, stripe_refund_id set (or cash), parent set
-- A refund mirrors its parent payment: a card refund carries a stripe_refund_id;
-- a cash refund carries none (payment_method_type='cash'), exactly as a cash
-- payment carries no stripe_charge_id.
-- Retry attempts become multiple rows sharing one invoice_id: each failed
-- attempt is its own row with status='failed'; the successful attempt (if any)
-- is another row with status='succeeded'.
CREATE TYPE charge_kind AS ENUM ('payment', 'refund');
CREATE TYPE charge_status AS ENUM ('pending', 'succeeded', 'failed');

CREATE TABLE member_charges (
    charge_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL
        CONSTRAINT fk_charge_invoice
        REFERENCES member_invoices(invoice_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL CONSTRAINT fk_charge_gym REFERENCES gyms(gym_id),

    -- The payer: whose Stripe customer/card was billed (mirrors the invoice's
    -- paid_by_member_id). The beneficiary set lives on the invoice (paid_for),
    -- not here. A refund row copies its parent payment's payer.
    paid_by_member_id UUID NOT NULL,

    kind charge_kind NOT NULL,
    status charge_status NOT NULL,

    amount INTEGER NOT NULL,  -- signed: payment >= 0, refund <= 0
    currency CHAR(3) NOT NULL DEFAULT 'usd',
    payment_method_type VARCHAR,  -- 'card' | 'us_bank_account' | 'cash' | ...
    card_last_four VARCHAR,  -- last 4 of the card, when the charge was on a card

    -- Exactly one of these is populated per row (enforced by kind-based checks).
    stripe_charge_id VARCHAR UNIQUE,
    stripe_refund_id VARCHAR UNIQUE,

    -- Refund linkage: which charge row this refund refunds.
    refunds_charge_id UUID
        CONSTRAINT fk_refund_parent
        REFERENCES member_charges(charge_id),

    charge_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    stripe_event_payload JSONB,

    PRIMARY KEY (charge_id),

    CONSTRAINT fk_charge_invoice_gym
        FOREIGN KEY (invoice_id, gym_id)
        REFERENCES member_invoices (invoice_id, gym_id),

    CONSTRAINT fk_charge_payer_gym
        FOREIGN KEY (paid_by_member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    -- Payment rules
    CONSTRAINT payment_amount_nonneg
        CHECK (kind <> 'payment' OR amount >= 0),
    CONSTRAINT payment_has_charge_id
        CHECK (kind <> 'payment' OR stripe_charge_id IS NOT NULL OR payment_method_type = 'cash'),
    CONSTRAINT payment_has_no_refund_id
        CHECK (kind <> 'payment' OR stripe_refund_id IS NULL),
    CONSTRAINT payment_has_no_parent
        CHECK (kind <> 'payment' OR refunds_charge_id IS NULL),

    -- Refund rules
    CONSTRAINT refund_amount_nonpos
        CHECK (kind <> 'refund' OR amount <= 0),
    CONSTRAINT refund_has_refund_id
        CHECK (kind <> 'refund' OR stripe_refund_id IS NOT NULL OR payment_method_type = 'cash'),
    CONSTRAINT refund_has_parent
        CHECK (kind <> 'refund' OR refunds_charge_id IS NOT NULL),
    CONSTRAINT refund_has_no_charge_id
        CHECK (kind <> 'refund' OR stripe_charge_id IS NULL)
);

CREATE INDEX idx_charges_invoice
    ON member_charges (invoice_id);

CREATE INDEX idx_charges_payer_gym_time
    ON member_charges (paid_by_member_id, gym_id, charge_time DESC);

CREATE INDEX idx_charges_gym_time
    ON member_charges (gym_id, charge_time DESC);

-- Cash-payment idempotency. A cash payment carries no stripe_charge_id, so the
-- stripe_charge_id UNIQUE (NULLs unconstrained) gives it no dedup key: the
-- twice-daily reconciler would re-record the same cash payment as a fresh row
-- on every run (revenue double-count). This partial unique index makes a
-- succeeded cash payment unique per invoice, so a re-record hits the insert's
-- ON CONFLICT DO NOTHING (the target-less form already arbitrates on this
-- index). Deliberately scoped to kind='payment' + cash + succeeded so it never
-- collides with a cash REFUND or a NULL-charge-id FAILED card attempt on the
-- same invoice -- both of which also leave stripe_charge_id NULL by design.
CREATE UNIQUE INDEX idx_charges_cash_payment_dedup
    ON member_charges (invoice_id)
    WHERE stripe_charge_id IS NULL
      AND kind = 'payment'
      AND status = 'succeeded'
      AND payment_method_type = 'cash';
