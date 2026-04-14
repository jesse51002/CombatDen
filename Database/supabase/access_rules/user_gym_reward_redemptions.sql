-- Enable Row Level Security
ALTER TABLE user_gym_reward_redemptions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own redemptions OR gym staff can read redemptions from their gyms
CREATE POLICY "Users and gym staff can view reward redemptions"
    ON user_gym_reward_redemptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE user_gym_profiles_unfiltered.crm_user_id = user_gym_reward_redemptions.crm_user_id
            AND user_gym_profiles_unfiltered.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_reward_redemptions.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (writes go through service_role)
REVOKE INSERT, UPDATE ON TABLE user_gym_reward_redemptions FROM authenticated;
