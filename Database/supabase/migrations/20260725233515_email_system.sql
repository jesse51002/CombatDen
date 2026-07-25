-- Hand-authored migration.
-- Adds the two tables behind CombatDen's own outbound email
-- (schemas/email_log.sql + schemas/email_suppressions.sql and their
-- access_rules/ counterparts). Purely additive: nothing existing is altered,
-- dropped, or recreated, so there are no dependent views to rebuild and no
-- security_invoker to preserve.
--
-- email_log is one row per intended message, claimed inside the transaction of
-- whatever triggered it (an employee insert, a member insert). That placement
-- is what makes a rolled-back create un-send its email, and what leaves a
-- recoverable row when a process dies mid-send. The UNIQUE on idempotency_key
-- is the entire no-duplicates mechanism — a double-clicked button, a retried
-- request, and a re-run sweep all collide on it.
--
-- email_suppressions records what an address has opted out OF. The scope enum
-- is what lets a member unsubscribe from app invites without ever losing the
-- transactional mail that carries their access, while a hard bounce ('all')
-- stops everything, because retrying a dead address is what damages a sending
-- domain's reputation.
--
-- Both are service-role-write-only. email_log gets a gym-scoped staff SELECT
-- policy; email_suppressions deliberately gets none, because a global
-- suppression (gym_id IS NULL) belongs to no gym and any policy permissive
-- enough to expose it would leak one tenant's bounced addresses to another.
--
-- No config.toml change: neither file needs an explicit schema_paths entry.
-- Both FK only gyms, which is the first path loaded, so the trailing
-- "./schemas/*.sql" glob picks them up in a safe position.

-- ============================================================
-- email_log
-- ============================================================

CREATE TYPE email_kind AS ENUM (
    'staff_onboarding',
    'member_app_invite'
);

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
    -- Polymorphic across gym_employees / members on purpose, so no FK: the log
    -- must outlive its subject being archived.
    subject_id UUID,
    recipient VARCHAR,
    idempotency_key TEXT NOT NULL,
    status email_status NOT NULL DEFAULT 'pending',
    payload JSONB NOT NULL,
    provider_message_id TEXT,
    attempts INT NOT NULL DEFAULT 0 CONSTRAINT attempts_non_negative CHECK (attempts >= 0),
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ,
    PRIMARY KEY (email_id),
    UNIQUE (idempotency_key),
    CONSTRAINT sent_matches_status
        CHECK ((status = 'sent') = (sent_at IS NOT NULL))
);

-- The retry sweep scans only unfinished rows; partial so it stays small as
-- sent history accumulates.
CREATE INDEX idx_email_log_retry
    ON email_log (created_at)
    WHERE status IN ('pending', 'failed');

-- Backs the per-person resend cap and the CRM's per-person send history.
CREATE INDEX idx_email_log_subject
    ON email_log (subject_id, kind, created_at DESC)
    WHERE subject_id IS NOT NULL;

-- Access rules (mirrors access_rules/email_log.sql).
ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON TABLE email_log FROM authenticated;

CREATE POLICY "Gym staff can view own gym email log"
    ON email_log
    FOR SELECT
    USING (is_gym_admin_or_owner(email_log.gym_id));

-- ============================================================
-- email_suppressions
-- ============================================================

CREATE TYPE email_suppression_scope AS ENUM (
    'marketing',
    'all'
);

CREATE TABLE email_suppressions (
    suppression_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    -- NULL = global (a hard bounce is dead for every gym).
    gym_id UUID CONSTRAINT fk_email_suppression_gym REFERENCES gyms(gym_id),
    email VARCHAR NOT NULL CONSTRAINT email_not_blank CHECK (email <> ''),
    scope email_suppression_scope NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (suppression_id)
);

-- Two partial unique indexes rather than one plain one: Postgres treats NULLs
-- as distinct, so a plain UNIQUE would let the same global bounce be recorded
-- unboundedly many times.
CREATE UNIQUE INDEX unique_email_suppression_gym
    ON email_suppressions (gym_id, lower(email), scope)
    WHERE gym_id IS NOT NULL;

CREATE UNIQUE INDEX unique_email_suppression_global
    ON email_suppressions (lower(email), scope)
    WHERE gym_id IS NULL;

-- Every send does one suppression lookup by address.
CREATE INDEX idx_email_suppressions_email
    ON email_suppressions (lower(email));

-- Access rules (mirrors access_rules/email_suppressions.sql). No SELECT policy
-- by design — see that file's header.
ALTER TABLE email_suppressions ENABLE ROW LEVEL SECURITY;

REVOKE INSERT, UPDATE, DELETE ON TABLE email_suppressions FROM authenticated;
