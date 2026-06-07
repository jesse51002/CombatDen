-- gym_discount_values is TRULY IMMUTABLE and service_role-write-only, exactly
-- like membership_plan_prices: clients never INSERT/UPDATE/DELETE a value row.
-- Authenticated users get SELECT only. The backend (service_role) creates a new
-- version and flips the prior one's is_active — a value row's columns are never
-- mutated, and versions are never deleted (they are a permanent paper trail
-- referenced by applied snapshots). There is no Stripe column here, so unlike
-- membership_plan_prices there is no hide_incomplete_stripe_records gate — a
-- value is valid the moment the backend inserts it.

-- Enable Row Level Security
ALTER TABLE gym_discount_values_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their discount value versions
CREATE POLICY "Gym staff can view discount values"
    ON gym_discount_values_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_discount_values_unfiltered.gym_id));

-- Column-level permissions: no INSERT/UPDATE/DELETE for authenticated. All
-- writes (insert a new version, flip the old is_active) go through service_role.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_discount_values_unfiltered FROM authenticated;

-- View-level permissions: block writes through the passthrough view.
REVOKE INSERT, UPDATE, DELETE ON gym_discount_values FROM authenticated;
