-- Enable Row Level Security
ALTER TABLE user_gym_charges ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own charges OR gym staff can read charges from their gyms
CREATE POLICY "Users and gym staff can view charges"
    ON user_gym_charges
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE user_gym_profiles_unfiltered.crm_user_id = user_gym_charges.crm_user_id
            AND user_gym_profiles_unfiltered.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_charges.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_charges FROM authenticated;
