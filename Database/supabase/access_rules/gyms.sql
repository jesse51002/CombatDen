-- ========================
-- gyms
-- ========================

-- Enable Row Level Security
ALTER TABLE gyms_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Owners and admins can view their gym
CREATE POLICY "Gym staff can view own gym"
    ON gyms_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(gyms_unfiltered.gym_id));

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE gyms_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON gyms FROM authenticated;

-- ========================
-- gym_employees
-- ========================

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
