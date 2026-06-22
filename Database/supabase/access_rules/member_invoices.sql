-- Enable Row Level Security
ALTER TABLE member_invoices ENABLE ROW LEVEL SECURITY;

-- Policy: a member reads an invoice they PAID (paid_by_member_id) or that was
-- FOR them (their id is in paid_for); gym staff read their gym's invoices.
CREATE POLICY "Users and gym staff can view invoices"
    ON member_invoices
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.user_id = auth.uid()
            AND (
                members.member_id = member_invoices.paid_by_member_id
                OR member_invoices.paid_for ? members.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoices.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_invoices FROM authenticated;
