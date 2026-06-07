-- Enable Row Level Security
ALTER TABLE member_membership_applied_discounts_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: the owning member can read their own applied discounts; gym staff can
-- read applied discounts for their gym.
CREATE POLICY "Users and gym staff can view applied membership discounts"
    ON member_membership_applied_discounts_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members m
            WHERE m.member_id = member_membership_applied_discounts_unfiltered.member_id
            AND m.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_membership_applied_discounts_unfiltered.gym_id)
    );

-- Restrictive policy: authenticated users only see applied discounts that are
-- real and synced — both a written-back Stripe coupon id AND a sync status past
-- the pending / preview-staging states. Kept in lockstep with the filtered
-- `member_membership_applied_discounts` view's WHERE
-- (schemas/member_membership_applied_discounts.sql) so the two never drift.
CREATE POLICY "hide_incomplete_stripe_records"
    ON member_membership_applied_discounts_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (
        stripe_coupon_id IS NOT NULL
        AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove')
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated. Apply (INSERT)
-- and remove (DELETE) and the system writebacks (UPDATE) all go through
-- service_role only (Stripe-gated rule).
REVOKE INSERT, UPDATE ON TABLE member_membership_applied_discounts_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view.
REVOKE INSERT, UPDATE ON member_membership_applied_discounts FROM authenticated;
