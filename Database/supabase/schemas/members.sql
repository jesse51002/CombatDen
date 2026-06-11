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

    -- Contact / freeze / linkage / Stripe billing (service_role-written only;
    -- NULL for engagement-only members).
    photo_url VARCHAR,
    phone VARCHAR,
    address VARCHAR,
    emergency_contact_name VARCHAR,
    emergency_contact_phone VARCHAR,
    emergency_contact_email VARCHAR,
    freeze_start_date DATE,
    freeze_end_date DATE,
    account_linked_to_id UUID,
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
        ),
    -- NOTE: a linked member MAY carry their own billing state. Billing is
    -- per PAYER (member_memberships.paid_by_member_id): a self-paying linked
    -- member legitimately holds their own stripe_sub_id_month, payment
    -- method/card columns, and freeze window. account_linked_to_id is the
    -- authorization layer only (who may pay for whom), never a billing gate.
    CONSTRAINT fk_member_linked_account
        FOREIGN KEY (account_linked_to_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- Partial unique index: a user can only have one member record per gym
CREATE UNIQUE INDEX unique_member_user_gym
    ON members (user_id, gym_id)
    WHERE user_id IS NOT NULL;

-- Unique index: each Stripe customer maps to exactly one member
CREATE UNIQUE INDEX idx_members_stripe_customer
    ON members (stripe_customer_id);

-- Index on the family-billing link. The payment sync resolves each family on
-- every billing op via `... OR account_linked_to_id = :parent`, and the
-- enforce_linked_account_hierarchy trigger checks `account_linked_to_id = NEW.member_id`
-- on every member insert/link — both seq-scan members without this. Partial
-- (the column is NULL for everyone except linked children) to stay lean.
CREATE INDEX idx_members_account_linked_to
    ON members (account_linked_to_id)
    WHERE account_linked_to_id IS NOT NULL;

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

-- Trigger: an account cannot be both a parent and a child in linked accounts
CREATE OR REPLACE FUNCTION enforce_linked_account_hierarchy()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        -- This member is becoming a child — ensure it is not already a parent
        IF EXISTS (
            SELECT 1 FROM members
            WHERE account_linked_to_id = NEW.member_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.member_id;
        END IF;

        -- Ensure the target parent is not itself a child
        IF EXISTS (
            SELECT 1 FROM members
            WHERE member_id = NEW.account_linked_to_id
              AND account_linked_to_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Cannot link to account % — it is already linked to another account',
                NEW.account_linked_to_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_linked_account_hierarchy
    BEFORE INSERT OR UPDATE OF account_linked_to_id ON members
    FOR EACH ROW EXECUTE FUNCTION enforce_linked_account_hierarchy();

-- Linked (family) discounts dissolved: a family discount is now a snapshot row
-- on member_membership_applied_discounts (discount_type = 'linked'), not a
-- person-level pointer. members.linked_discount_id and its type-check trigger
-- are gone; account_linked_to_id (the family-billing link itself) is unchanged.

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
