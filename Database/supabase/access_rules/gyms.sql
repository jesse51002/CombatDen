-- ========================
-- gyms
-- ========================

ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

-- Owners and admins can view their gym
CREATE POLICY "Gym staff can view own gym"
    ON gyms
    FOR SELECT
    USING (is_gym_admin_or_owner(gyms.gym_id));

-- Owners and admins can update their gym (Stripe Connect state is service_role-only — see REVOKE below)
CREATE POLICY "Gym staff can update own gym"
    ON gyms
    FOR UPDATE
    USING (is_gym_admin_or_owner(gyms.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gyms.gym_id));

-- Identity columns stay immutable; Stripe Connect columns are written by service_role only
REVOKE UPDATE (gym_id, created_at, stripe_account_id, stripe_onboarding_status) ON TABLE gyms FROM authenticated;

-- ========================
-- gym_employees
-- ========================

ALTER TABLE gym_employees ENABLE ROW LEVEL SECURITY;

-- Any employee can view other employees at their gym
CREATE POLICY "Employees can view gym staff"
    ON gym_employees
    FOR SELECT
    USING (is_gym_employee(gym_employees.gym_id));

-- Owners and admins can insert employees for their gym
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

-- Owners and admins can update employees at their gym
CREATE POLICY "Owners and admins can update employees"
    ON gym_employees
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_employees.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_employees.gym_id));

-- Identity columns stay immutable
REVOKE UPDATE (employee_id, gym_id, created_at) ON TABLE gym_employees FROM authenticated;
