-- Enable Row Level Security
ALTER TABLE gym_class_exceptions ENABLE ROW LEVEL SECURITY;

-- Policy: All employees can view exceptions
CREATE POLICY "Gym employees can view exceptions"
    ON gym_class_exceptions
    FOR SELECT
    USING (is_gym_employee(gym_class_exceptions.gym_id));

-- Policy: Members can view exceptions for their gym
CREATE POLICY "Members can view exceptions"
    ON gym_class_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_class_exceptions.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert exceptions
CREATE POLICY "Gym staff can insert exceptions"
    ON gym_class_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_class_exceptions.gym_id));

-- Policy: Gym staff can update exceptions
CREATE POLICY "Gym staff can update exceptions"
    ON gym_class_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_class_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_class_exceptions.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (exception_id, schedule_id, gym_id, original_date, created_at) ON TABLE gym_class_exceptions FROM authenticated;
