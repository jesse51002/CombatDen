-- Enable Row Level Security
ALTER TABLE user_gym_invoice_line_items ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read line items on their own invoices OR gym staff can read line items from their gyms
CREATE POLICY "Users and gym staff can view invoice line items"
    ON user_gym_invoice_line_items
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_invoices inv
            JOIN user_gym_profiles_unfiltered p ON p.crm_user_id = inv.crm_user_id
            WHERE inv.invoice_id = user_gym_invoice_line_items.invoice_id
            AND p.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_invoice_line_items.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_invoice_line_items FROM authenticated;
