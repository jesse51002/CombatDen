-- Enable Row Level Security
ALTER TABLE gym_discounts_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their discounts
CREATE POLICY "Gym staff can view discounts"
    ON gym_discounts_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id));

-- Restrictive policy: authenticated users cannot see discounts without a Stripe coupon sync
CREATE POLICY "hide_incomplete_stripe_records"
    ON gym_discounts_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (stripe_coupon_id IS NOT NULL);

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE gym_discounts_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON gym_discounts FROM authenticated;
