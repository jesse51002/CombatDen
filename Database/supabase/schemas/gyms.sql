CREATE TYPE employee_type AS ENUM ('owner', 'admin', 'trainer');

-- Per-employee CRM admin-app appearance preference. 'system' follows the OS.
CREATE TYPE theme_mode AS ENUM ('system', 'light', 'dark');

CREATE TYPE stripe_onboarding_status AS ENUM (
    'not_started', 'pending', 'complete', 'disabled'
);

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
    -- Stripe Connect onboarding state (service_role-only writes; see access_rules/gyms.sql)
    stripe_account_id TEXT UNIQUE,
    stripe_onboarding_status stripe_onboarding_status NOT NULL DEFAULT 'not_started',
    -- The ThemeService design id selected for this gym's member app (branding).
    -- ThemeService remains a separate service; this is just the chosen design's id.
    -- The "app id" is NOT stored here — it is a single hardcoded API/Settings
    -- constant (one app for now). Client-editable, so absent from immutable GYMS.
    theme_design_id TEXT,
    PRIMARY KEY (gym_id)
);

-- ============================================================
-- gym_employees (co-located to avoid circular RLS dependency)
-- ============================================================

CREATE TABLE gym_employees (
    employee_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    -- Login principal link. ONLY owner/admin rows may carry one: a
    -- 'trainer' row is instructor DATA (a name/photo shown on classes),
    -- never an account — enforced by chk_trainer_has_no_account below,
    -- which is what makes is_gym_employee() (and every backend staff
    -- check) owner/admin-only by construction.
    user_id UUID CONSTRAINT fk_employee_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_employee_gym REFERENCES gyms(gym_id),
    employee_type employee_type NOT NULL,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    phone VARCHAR,
    email VARCHAR,
    employee_pic_url VARCHAR,
    employee_public_description VARCHAR,
    -- CRM admin-app theme this employee chose (client-editable; see immutable_columns).
    theme_preference theme_mode NOT NULL DEFAULT 'system',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (employee_id),
    UNIQUE (user_id, gym_id),
    UNIQUE (employee_id, gym_id),
    -- Trainers have no accounts at all (see user_id comment above).
    CONSTRAINT chk_trainer_has_no_account
        CHECK (employee_type <> 'trainer' OR user_id IS NULL)
);

-- ============================================================
-- Security-definer helpers (bypass RLS to avoid recursion)
-- ============================================================

CREATE FUNCTION is_gym_employee(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND gym_employees.user_id = auth.uid()
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
        AND gym_employees.user_id = auth.uid()
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

-- Partial unique index: a user can only have one employee record per gym
CREATE UNIQUE INDEX unique_employee_user_gym
    ON gym_employees (user_id, gym_id)
    WHERE user_id IS NOT NULL;
