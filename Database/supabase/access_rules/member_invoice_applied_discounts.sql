-- Enable Row Level Security
ALTER TABLE member_invoice_applied_discounts ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read applied discounts on their own invoices OR gym staff can read applied discounts from their gyms
CREATE POLICY "Users and gym staff can view applied discounts"
    ON member_invoice_applied_discounts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON lower(m.email) = lower(auth.jwt() ->> 'email')
            WHERE inv.invoice_id = member_invoice_applied_discounts.invoice_id
            AND (
                m.member_id = inv.paid_by_member_id
                OR inv.paid_for ? m.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoice_applied_discounts.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_invoice_applied_discounts FROM authenticated;
