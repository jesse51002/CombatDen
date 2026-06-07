-- Enable Row Level Security
ALTER TABLE member_invoices ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own invoices OR gym staff can read invoices from their gyms
CREATE POLICY "Users and gym staff can view invoices"
    ON member_invoices
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_invoices.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_invoices.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_invoices FROM authenticated;
