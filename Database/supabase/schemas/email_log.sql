-- Every email CombatDen itself sends. One row per intended message, written by
-- the backend (service_role) only — clients never write here.
--
-- The row is claimed INSIDE the transaction of whatever triggered it (an
-- employee insert, a member insert), so a rolled-back operation un-sends its
-- email for free and a crash mid-send leaves a row the reconciler's retry sweep
-- recovers. Delivery itself happens after that transaction commits, detached.
--
-- This table is simultaneously the audit trail ("what did we send that person,
-- and where did it actually go") and the retry queue. Rows are never deleted.
--
-- NOTE: this covers only CombatDen's OWN mail. Supabase Auth's confirmation /
-- password-reset mail (GoTrue) and Stripe's card-declined mail (sent from each
-- gym's own connected account) are separate channels that never touch this
-- table.

-- Which email. Every value has a registered spec in the backend
-- (FastApiBackend/src/emails/emails_registry.py) naming its category, its
-- template files, and its payload model. Adding a kind is an ALTER TYPE ...
-- ADD VALUE migration plus that registry entry — and the migration must be
-- applied before any code referencing the new value ships.
CREATE TYPE email_kind AS ENUM (
    'staff_onboarding',
    'member_app_invite'
);

-- Lifecycle. 'pending' = claimed, not yet delivered (the retry sweep picks
-- these up). 'sent' and 'suppressed' are terminal successes; 'failed' is
-- retryable until the attempt ceiling.
--
-- 'held' is terminal-by-policy and deliberately NOT retryable: the kind was
-- absent from the backend's EMAIL_ENABLED_KINDS at claim time (e.g. member
-- invites while the member app is not yet installable). The row records that
-- staff asked, but the sweep skips it forever — otherwise enabling a kind
-- months later would drain the whole backlog at once and mail everyone who
-- ever joined. Releasing held rows is a deliberate act, never a side effect of
-- turning a flag on.
CREATE TYPE email_status AS ENUM (
    'pending',
    'sent',
    'failed',
    'suppressed',
    'held'
);

CREATE TABLE email_log (
    email_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_email_log_gym REFERENCES gyms(gym_id),
    kind email_kind NOT NULL,
    -- The person this email is ABOUT (a gym_employees or members row).
    -- Deliberately NOT a foreign key: it is polymorphic across two tables, and
    -- the log must survive its subject being archived. It exists so the
    -- per-person resend cap is an indexed count rather than a JSONB dig; any
    -- kind that supports resending must set it.
    subject_id UUID,
    -- The address actually used, resolved from the DB at send time and then
    -- frozen. NULL until the send is attempted. This is the audit answer to
    -- "where did it really go" — never trust the payload for that.
    recipient VARCHAR,
    -- The whole no-duplicates mechanism. Built by the backend from the payload
    -- (e.g. 'staff_onboarding:<employee_id>:<resend_seq>'), so a double-clicked
    -- button, a retried request, and a re-run sweep all collide here and only
    -- one row survives. A DELIBERATE resend bumps its own counter inside the
    -- key, which is what makes it a genuinely new send rather than a no-op.
    idempotency_key TEXT NOT NULL,
    status email_status NOT NULL DEFAULT 'pending',
    -- The validated payload, so a retry needs nothing from the original caller.
    payload JSONB NOT NULL,
    -- The mail provider's id for the delivered message — the thread back to
    -- their dashboard when someone asks "did this actually go out".
    provider_message_id TEXT,
    attempts INT NOT NULL DEFAULT 0 CONSTRAINT attempts_non_negative CHECK (attempts >= 0),
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    PRIMARY KEY (email_id),
    UNIQUE (idempotency_key),
    -- sent_at is set exactly when the row reaches 'sent' (mirrors the
    -- resolved_matches_status pattern on member_reward_redemptions).
    CONSTRAINT sent_matches_status
        CHECK ((status = 'sent') = (sent_at IS NOT NULL))
);

-- The reconciler's retry sweep scans only unfinished rows, oldest first.
-- Partial so it stays small no matter how much successfully-sent history
-- accumulates.
CREATE INDEX idx_email_log_retry
    ON email_log (created_at)
    WHERE status IN ('pending', 'failed');

-- Backs the per-person resend cap ("how many of this kind have we sent this
-- person in the trailing hour") and the CRM's per-person send history.
CREATE INDEX idx_email_log_subject
    ON email_log (subject_id, kind, created_at DESC)
    WHERE subject_id IS NOT NULL;
