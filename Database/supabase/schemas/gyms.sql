
CREATE TABLE gyms_unfiltered (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_name VARCHAR NOT NULL CHECK (gym_name <> ''),
    gym_description VARCHAR,
    timezone TEXT NOT NULL DEFAULT 'America/Chicago'
        CONSTRAINT gyms_timezone_valid CHECK (now() AT TIME ZONE timezone IS NOT NULL),
    stripe_account_id VARCHAR,
    stripe_onboarding_status VARCHAR NOT NULL DEFAULT 'not_started'
        CHECK (stripe_onboarding_status IN ('not_started', 'pending', 'complete', 'disabled')),
    PRIMARY KEY (gym_id)
);

-- View: only exposes gyms with a completed Stripe account link
CREATE VIEW gyms
WITH (security_invoker = true)
AS
SELECT * FROM gyms_unfiltered
WHERE stripe_account_id IS NOT NULL;

ALTER VIEW gyms SET (security_invoker = true);

-- ============================================================
-- gym_employees (co-located to avoid circular RLS dependency)
-- ============================================================

CREATE TABLE gym_employees (
    employee_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_employee_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_employee_gym REFERENCES gyms_unfiltered(gym_id),
    employee_type VARCHAR NOT NULL CHECK (employee_type IN ('owner', 'admin', 'trainer')),
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    phone VARCHAR,
    email VARCHAR,
    employee_pic_url VARCHAR,
    employee_public_description VARCHAR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (employee_id),
    UNIQUE (user_id, gym_id),
    UNIQUE (employee_id, gym_id)
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
