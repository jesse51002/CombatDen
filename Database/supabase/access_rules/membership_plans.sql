-- Enable Row Level Security
ALTER TABLE membership_plans_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their plans
CREATE POLICY "Gym staff can view plans"
    ON membership_plans_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(membership_plans_unfiltered.gym_id));

-- Policy: Members can view plans for their gym
CREATE POLICY "Members can view gym plans"
    ON membership_plans_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = membership_plans_unfiltered.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Restrictive policy: authenticated users cannot see plans without a Stripe product sync
CREATE POLICY "hide_incomplete_stripe_records"
    ON membership_plans_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (stripe_product_id IS NOT NULL);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE ON TABLE membership_plans_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON membership_plans FROM authenticated;
