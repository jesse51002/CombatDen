-- Enable Row Level Security
ALTER TABLE membership_plan_prices_unfiltered ENABLE ROW LEVEL SECURITY;

-- SELECT only (stripe rule: no INSERT/UPDATE for authenticated)
CREATE POLICY "Gym staff can view plan prices"
    ON membership_plan_prices_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(membership_plan_prices_unfiltered.gym_id));

CREATE POLICY "Members can view plan prices"
    ON membership_plan_prices_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = membership_plan_prices_unfiltered.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- Restrictive policy: authenticated users cannot see prices without a Stripe price sync
CREATE POLICY "hide_incomplete_stripe_records"
    ON membership_plan_prices_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (stripe_price_id IS NOT NULL);

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE membership_plan_prices_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON membership_plan_prices FROM authenticated;
