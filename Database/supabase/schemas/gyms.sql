
CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_name VARCHAR NOT NULL CHECK (gym_name <> ''),
    gym_description VARCHAR,
    PRIMARY KEY (gym_id)
);

-- ============================================================
-- gym_employees (co-located to avoid circular RLS dependency)
-- ============================================================

CREATE TABLE gym_employees (
    employee_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_employee_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_employee_gym REFERENCES gyms(gym_id),
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


-- Enable Row Level Security
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;


-- Policy: Owners and admins can view their gym
CREATE POLICY "Gym staff can view own gym"
    ON gyms
    FOR SELECT
    USING (is_gym_admin_or_owner(gyms.gym_id));

-- Policy: Owners and admins can update their gym
CREATE POLICY "Gym staff can update own gym"
    ON gyms
    FOR UPDATE
    USING (is_gym_admin_or_owner(gyms.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gyms.gym_id));

-- Policy: Any authenticated user can create a gym
CREATE POLICY "Authenticated users can create gyms"
    ON gyms
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (gym_id) ON TABLE gyms FROM authenticated;



-- Partial unique index: a user can only have one employee record per gym
CREATE UNIQUE INDEX unique_employee_user_gym
    ON gym_employees (user_id, gym_id)
    WHERE user_id IS NOT NULL;

-- Enable Row Level Security
ALTER TABLE gym_employees ENABLE ROW LEVEL SECURITY;

-- Policy: Any employee can view other employees at their gym
CREATE POLICY "Employees can view gym staff"
    ON gym_employees
    FOR SELECT
    USING (is_gym_employee(gym_employees.gym_id));

-- Policy: Owners and admins can insert employees for their gym
-- Bootstrap case: user can insert themselves as 'owner' if no owner exists yet
CREATE POLICY "Owners and admins can insert employees"
    ON gym_employees
    FOR INSERT
    TO authenticated
    WITH CHECK (
        is_gym_admin_or_owner(gym_employees.gym_id)
        OR (
            gym_employees.employee_type = 'owner'
            AND gym_employees.user_id = auth.uid()
            AND NOT gym_has_owner(gym_employees.gym_id)
        )
    );

-- Policy: Owners and admins can update employees at their gym
CREATE POLICY "Owners and admins can update employees"
    ON gym_employees
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_employees.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_employees.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (employee_id, gym_id, created_at) ON TABLE gym_employees FROM authenticated;
