-- Enable Row Level Security
ALTER TABLE gym_classes ENABLE ROW LEVEL SECURITY;

-- Policy: All employees can view classes
CREATE POLICY "Gym employees can view classes"
    ON gym_classes
    FOR SELECT
    USING (is_gym_employee(gym_classes.gym_id));

-- Policy: Members can view classes for their gym
CREATE POLICY "Members can view classes"
    ON gym_classes
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_classes.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert classes
CREATE POLICY "Gym staff can insert classes"
    ON gym_classes
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_classes.gym_id));

-- Policy: Gym staff can update classes
CREATE POLICY "Gym staff can update classes"
    ON gym_classes
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_classes.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_classes.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (class_id, gym_id, created_at) ON TABLE gym_classes FROM authenticated;
