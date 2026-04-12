-- Enable Row Level Security
ALTER TABLE gym_class_schedules ENABLE ROW LEVEL SECURITY;

-- Policy: All employees can view schedules
CREATE POLICY "Gym employees can view schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (is_gym_employee(gym_class_schedules.gym_id));

-- Policy: Members can view schedules for active classes in their gym
CREATE POLICY "Members can view schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gym_classes
            WHERE gym_classes.class_id = gym_class_schedules.class_id
            AND gym_classes.is_active = true
        )
        AND EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_class_schedules.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert schedules
CREATE POLICY "Gym staff can insert schedules"
    ON gym_class_schedules
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_class_schedules.gym_id));

-- Policy: Gym staff can update schedules
CREATE POLICY "Gym staff can update schedules"
    ON gym_class_schedules
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_class_schedules.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_class_schedules.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (schedule_id, class_id, gym_id, start_date, created_at) ON TABLE gym_class_schedules FROM authenticated;
