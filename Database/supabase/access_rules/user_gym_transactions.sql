-- Enable Row Level Security
ALTER TABLE user_gym_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own transactions OR gym staff can read transactions from their gyms
CREATE POLICY "Users and gym staff can view transactions"
    ON user_gym_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_transactions.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_transactions FROM authenticated;
