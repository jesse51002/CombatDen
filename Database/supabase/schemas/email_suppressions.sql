-- Addresses CombatDen must stop mailing: member unsubscribes and hard bounces.
-- Checked before every send. Written by the backend (service_role) only.
--
-- This exists because CombatDen's own mail splits into two characters, and the
-- split is load-bearing rather than cosmetic:
--
--   * a STAFF nudge is transactional — it carries the link that grants someone
--     access to the CRM, so it must reach them even if they once opted out of
--     other mail;
--   * a MEMBER app invite is marketing — it is a pitch with a call to action,
--     and a member who does not remember asking for it may well mark it spam.
--
-- Each email kind declares its category in the backend registry
-- (FastApiBackend/src/emails/emails_registry.py); this table records what a
-- given address has opted out OF.

-- How far a suppression reaches.
--   'marketing' — an unsubscribe. Blocks marketing kinds only; a transactional
--                 kind still sends, because opting out of a pitch must never
--                 cost someone the link that gets them into the product.
--   'all'       — a hard bounce or an explicit block. The address is dead or
--                 hostile, so nothing is sent, transactional included: retrying
--                 a dead address is what damages a sending domain's reputation,
--                 and that reputation is what keeps login mail arriving.
CREATE TYPE email_suppression_scope AS ENUM (
    'marketing',
    'all'
);

CREATE TABLE email_suppressions (
    suppression_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    -- The gym whose mail this address opted out of. NULL = GLOBAL, used for a
    -- hard bounce: a dead mailbox is dead for every gym, so it is pointless
    -- (and reputationally expensive) to keep discovering that per tenant.
    gym_id UUID CONSTRAINT fk_email_suppression_gym REFERENCES gyms(gym_id),
    -- Lowercase-normalized, matching the identity convention used by
    -- gym_employees.email and members.email.
    email VARCHAR NOT NULL CONSTRAINT email_not_blank CHECK (email <> ''),
    scope email_suppression_scope NOT NULL,
    -- Free text: 'unsubscribed', 'hard_bounce', a provider reason code.
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (suppression_id)
);

-- One suppression per (address, scope) per gym. Split into two partial unique
-- indexes because NULL gym_id means "global" and Postgres treats NULLs as
-- distinct in a plain unique index — which would let the same global bounce be
-- recorded unboundedly many times. Mirrors the partial-index approach used by
-- unique_employee_email_gym.
CREATE UNIQUE INDEX unique_email_suppression_gym
    ON email_suppressions (gym_id, lower(email), scope)
    WHERE gym_id IS NOT NULL;

CREATE UNIQUE INDEX unique_email_suppression_global
    ON email_suppressions (lower(email), scope)
    WHERE gym_id IS NULL;

-- Every send does one suppression lookup by address, so it is the hot path.
CREATE INDEX idx_email_suppressions_email
    ON email_suppressions (lower(email));
