-- Enable Row Level Security
ALTER TABLE user_activities ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own activities OR gym staff can read activities from their gyms
CREATE POLICY "Users and gym staff can view activities"
    ON user_activities
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = user_activities.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_activities.gym_id)
    );

-- Policy: Gym staff can insert activities for their gyms
CREATE POLICY "Gym staff can insert activities"
    ON user_activities
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(user_activities.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (activity_id, crm_user_id, gym_id, time) ON TABLE user_activities FROM authenticated;
