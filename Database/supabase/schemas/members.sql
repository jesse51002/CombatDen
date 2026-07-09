-- A member is the unified identity + billing/contact profile for a person at
-- a gym, keyed (member_id, gym_id). Core identity (name, email, points, rank)
-- is client-writable by the member / gym staff. The merged contact, freeze,
-- linkage and Stripe billing columns are written by service_role only
-- (column-level grants in access_rules/members.sql); they are simply NULL for
-- engagement-only members who have no billing. This mirrors the original CRM's
-- single user_gym_profiles table (identity + billing in one row).
CREATE TABLE members (
    member_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_member_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_member_gym REFERENCES gyms(gym_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_class TIMESTAMPTZ,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    email VARCHAR,
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    current_rank_id UUID,
    -- Leaf position within current_rank_id's main rank. NULL when that rank
    -- has sub_rank_count = 0. Enforced non-null-when-count>0 by the ranks
    -- service on every assign/promote path (only the ranks endpoints write it).
    current_sub_index INTEGER CHECK (current_sub_index IS NULL OR current_sub_index >= 0),

    -- RAG video-taste profile (backend-built, service_role-only). One prose
    -- summary + one embedding per member, built lazily by the backend and
    -- rebuilt when stale (video_profile_built_at); all NULL until first built.
    -- The embedding is pinned to settings.video_embedding_dim — the same model
    -- + dimension contract as video_rag.embedding (they are compared by cosine).
    video_profile_summary TEXT,
    video_profile_embedding vector(3072),
    video_profile_embedding_model TEXT,
    video_profile_built_at TIMESTAMPTZ,

    -- Contact / freeze / Stripe billing (service_role-written only;
    -- NULL for engagement-only members).
    photo_url VARCHAR,
    phone VARCHAR,
    address VARCHAR,
    emergency_contact_name VARCHAR,
    emergency_contact_phone VARCHAR,
    emergency_contact_email VARCHAR,
    freeze_start_date DATE,
    freeze_end_date DATE,
    stripe_customer_id VARCHAR,
    stripe_sub_id_month VARCHAR,
    stripe_payment_method_id VARCHAR,
    payment_type VARCHAR,
    card_brand VARCHAR,
    card_last_four VARCHAR(4),
    card_exp_month INTEGER,
    card_exp_year INTEGER,
    total_monthly_recurring_price INTEGER NOT NULL DEFAULT 0
        CHECK (total_monthly_recurring_price >= 0),

    PRIMARY KEY (member_id),
    UNIQUE (member_id, gym_id),
    CONSTRAINT fk_member_current_rank
        FOREIGN KEY (current_rank_id, gym_id)
        REFERENCES gym_ranks (rank_id, gym_id),
    CONSTRAINT freeze_dates_must_be_paired
        CHECK (
            (freeze_start_date IS NULL AND freeze_end_date IS NULL)
            OR (freeze_start_date IS NOT NULL AND freeze_end_date IS NOT NULL)
        )
    -- NOTE: a member MAY carry their own billing state. Billing is per PAYER
    -- (member_memberships.paid_by_member_id): a member paid for by an authorized
    -- payer still legitimately holds their own stripe_sub_id_month, payment
    -- method/card columns, and freeze window. Authorization (who may pay for
    -- whom) lives in member_authorized_payers, never a billing gate on this row.
);

-- Partial unique index: a user can only have one member record per gym
CREATE UNIQUE INDEX unique_member_user_gym
    ON members (user_id, gym_id)
    WHERE user_id IS NOT NULL;

-- Unique index: each Stripe customer maps to exactly one member
CREATE UNIQUE INDEX idx_members_stripe_customer
    ON members (stripe_customer_id);

-- Trigger: once user_id is set, it cannot be changed to a different value
CREATE OR REPLACE FUNCTION prevent_user_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (member_id: %)', OLD.member_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_user_id_overwrite
    BEFORE UPDATE OF user_id ON members
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_overwrite();

-- Trigger: stripe_customer_id is immutable once set
CREATE OR REPLACE FUNCTION prevent_stripe_customer_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (member_id: %)', OLD.member_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_stripe_customer_id_overwrite
    BEFORE UPDATE OF stripe_customer_id ON members
    FOR EACH ROW EXECUTE FUNCTION prevent_stripe_customer_id_overwrite();

-- The family link lives in the member_authorized_payers junction (the
-- many-to-many authorization layer), so members carries no link column or
-- hierarchy trigger.

-- Filtered view: members with a completed Stripe customer sync. Billing flows
-- read through this so half-synced rows are never surfaced. `members` is the
-- single source-of-truth table; this is just a billing-complete window onto it
-- (mirrors the original CRM's user_gym_profiles_unfiltered -> user_gym_profiles
-- base-table + filtered-view pattern).
CREATE VIEW member_billing_profile
WITH (security_invoker = true)
AS
SELECT * FROM members WHERE stripe_customer_id IS NOT NULL;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_billing_profile SET (security_invoker = true);
