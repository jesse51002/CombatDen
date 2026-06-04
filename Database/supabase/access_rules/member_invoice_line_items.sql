-- Enable Row Level Security
ALTER TABLE member_invoice_line_items ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read line items on their own invoices OR gym staff can read line items from their gyms
CREATE POLICY "Users and gym staff can view invoice line items"
    ON member_invoice_line_items
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON m.member_id = inv.member_id
            WHERE inv.invoice_id = member_invoice_line_items.invoice_id
            AND m.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_invoice_line_items.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_invoice_line_items FROM authenticated;
