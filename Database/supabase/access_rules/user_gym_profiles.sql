-- Enable Row Level Security
ALTER TABLE user_gym_profiles_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own profile OR gym staff can read profiles from their gyms
CREATE POLICY "Users and gym staff can view profiles"
    ON user_gym_profiles_unfiltered
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR is_gym_admin_or_owner(user_gym_profiles_unfiltered.gym_id)
    );

-- Restrictive policy: authenticated users cannot see profiles without a Stripe customer sync
CREATE POLICY "hide_incomplete_stripe_records"
    ON user_gym_profiles_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (stripe_customer_id IS NOT NULL);

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_profiles_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON user_gym_profiles FROM authenticated;
