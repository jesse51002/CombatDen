-- Enable Row Level Security
ALTER TABLE gym_classes_log ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own class logs OR gym staff can read logs from their gyms
CREATE POLICY "Users and gym staff can view class logs"
    ON gym_classes_log
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = gym_classes_log.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(gym_classes_log.gym_id)
    );

-- Policy: Gym staff can insert class logs
CREATE POLICY "Gym staff can insert class logs"
    ON gym_classes_log
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_classes_log.gym_id));

-- Column-level permissions: logs are immutable
REVOKE UPDATE ON TABLE gym_classes_log FROM authenticated;
