-- Enable Row Level Security
ALTER TABLE user_gym_invoices ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own invoices OR gym staff can read invoices from their gyms
CREATE POLICY "Users and gym staff can view invoices"
    ON user_gym_invoices
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE user_gym_profiles_unfiltered.crm_user_id = user_gym_invoices.crm_user_id
            AND user_gym_profiles_unfiltered.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_invoices.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_invoices FROM authenticated;
