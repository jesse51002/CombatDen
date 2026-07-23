CREATE TYPE employee_type AS ENUM ('owner', 'admin', 'trainer', 'front_desk');

-- Per-employee CRM admin-app appearance preference. 'system' follows the OS.
CREATE TYPE theme_mode AS ENUM ('system', 'light', 'dark');

CREATE TYPE stripe_onboarding_status AS ENUM (
    'not_started', 'pending', 'complete', 'disabled'
);

-- Per-gym sub-rank style. Consumed by gym_ranks (a main rank with
-- sub_rank_count > 0) and mirrored onto rank_presets.implied_sub_rank_type.
-- 'none' (the default) = the gym has main belts but NO sub-positions: every
-- rank behaves as its own leaf (effective sub_rank_count 0) and members carry
-- a NULL current_sub_index. 'stripes' / 'div' only change the derived LABELS.
-- Switching TO 'none' is persist-only — it never wipes a rank's stored
-- sub_rank_count / sub_rank_image_overrides; they reactivate on a switch back.
CREATE TYPE sub_rank_type AS ENUM ('none', 'stripes', 'div');

CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_name VARCHAR NOT NULL CHECK (gym_name <> ''),
    gym_description VARCHAR,
    -- The gym's uploaded logo (CDN URL). NULL = no logo uploaded yet;
    -- clients fall back to a default mark client-side.
    logo_url TEXT,
    timezone TEXT NOT NULL DEFAULT 'America/Chicago'
        CONSTRAINT gyms_timezone_valid CHECK (now() AT TIME ZONE timezone IS NOT NULL),
    is_rank_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    -- Per-gym sub-rank style. Every main rank with sub_rank_count > 0 uses
    -- this. Sub-rank LABELS are derived from (sub_rank_type, sub_index),
    -- never stored. Default 'none' = no sub-ranks (most gyms). Writable via
    -- the gym-update path; from_preset sets it. Changing it reconciles every
    -- member's current_sub_index to stay leaf-valid (ranks domain), never
    -- touching the persisted per-rank counts / image overrides.
    sub_rank_type sub_rank_type NOT NULL DEFAULT 'none',
    -- Stripe Connect onboarding state (service_role-only writes; see access_rules/gyms.sql)
    stripe_account_id TEXT UNIQUE,
    stripe_onboarding_status stripe_onboarding_status NOT NULL DEFAULT 'not_started',
    -- The ThemeService design id selected for this gym's member app (branding).
    -- ThemeService remains a separate service; this is just the chosen design's id.
    -- The "app id" is NOT stored here — it is a single hardcoded API/Settings
    -- constant (one app for now). Client-editable, so absent from immutable GYMS.
    theme_design_id TEXT,
    -- Per-gym white-label member-app store listings, feeding the public
    -- app-download page in Kiosk Mode's app-adoption funnel. NULL = the gym
    -- has not set its own listing, so the public GET .../app-links endpoint
    -- falls back to the CombatDen default listing (Settings). Client-editable
    -- (white-label), so both stay OUT of the immutable GYMS frozenset.
    app_store_url TEXT,
    play_store_url TEXT,
    PRIMARY KEY (gym_id)
);

-- ============================================================
-- gym_employees (co-located to avoid circular RLS dependency)
-- ============================================================

CREATE TABLE gym_employees (
    employee_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_employee_gym REFERENCES gyms(gym_id),
    employee_type employee_type NOT NULL,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    phone VARCHAR,
    -- Identity link. Lowercase-normalized. A verified auth account with this
    -- email = this person's access to the gym (matched via auth.jwt() ->>
    -- 'email' in the security-definer helpers below, not a user_id FK). Only
    -- a 'trainer' row may leave this NULL (see chk_principal_has_email) — a
    -- trainer row is instructor DATA (a name/photo shown on classes), never
    -- a login principal.
    email VARCHAR,
    employee_pic_url VARCHAR,
    employee_public_description VARCHAR,
    -- CRM admin-app theme this employee chose (client-editable; see immutable_columns).
    theme_preference theme_mode NOT NULL DEFAULT 'system',
    -- Soft-archive: a revoked employee. Rows are never hard-deleted (the
    -- instructor + waiver-operator FKs reference them). Excluded from every
    -- auth check (is_gym_employee / is_gym_admin_or_owner) and the employees
    -- list.
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (employee_id),
    UNIQUE (employee_id, gym_id),
    -- Only a login-carrying role (owner/admin/front_desk) must carry an
    -- email — a trainer row may legitimately be email-less instructor data.
    CONSTRAINT chk_principal_has_email
        CHECK (employee_type = 'trainer' OR email IS NOT NULL)
);

-- ============================================================
-- Security-definer helpers (bypass RLS to avoid recursion)
-- ============================================================

-- Any login-carrying, non-archived employee (matched by verified email).
CREATE FUNCTION is_gym_employee(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND lower(gym_employees.email) = lower(auth.jwt() ->> 'email')
        AND gym_employees.archived_at IS NULL
    );
$$;

CREATE FUNCTION is_gym_admin_or_owner(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND lower(gym_employees.email) = lower(auth.jwt() ->> 'email')
        AND gym_employees.archived_at IS NULL
        AND gym_employees.employee_type IN ('owner', 'admin')
    );
$$;

CREATE FUNCTION gym_has_owner(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.employee_type = 'owner'
    );
$$;

-- Partial unique index: one employee row per email per gym (case-insensitive;
-- the email identity key).
CREATE UNIQUE INDEX unique_employee_email_gym
    ON gym_employees (gym_id, lower(email))
    WHERE email IS NOT NULL;
