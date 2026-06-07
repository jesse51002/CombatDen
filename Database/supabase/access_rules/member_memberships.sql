-- Enable Row Level Security
ALTER TABLE member_memberships_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view memberships for their gyms
CREATE POLICY "Gym staff can view memberships"
    ON member_memberships_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(member_memberships_unfiltered.gym_id));

-- Policy: Members can view their own memberships
CREATE POLICY "Members can view own memberships"
    ON member_memberships_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_memberships_unfiltered.member_id
            AND members.user_id = auth.uid()
        )
    );

-- Restrictive policy: authenticated users only see memberships that are real and
-- synced — both a Stripe item id (was actually put on Stripe) AND a sync status
-- past the pending / preview-staging states. Kept in lockstep with the filtered
-- `member_memberships` view's WHERE (schemas/member_memberships.sql) so the two
-- never drift.
CREATE POLICY "hide_incomplete_stripe_records"
    ON member_memberships_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (
        stripe_item_id IS NOT NULL
        AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove')
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE ON TABLE member_memberships_unfiltered FROM authenticated;

-- View-level permissions: block writes through the filtered view
REVOKE INSERT, UPDATE ON member_memberships FROM authenticated;
