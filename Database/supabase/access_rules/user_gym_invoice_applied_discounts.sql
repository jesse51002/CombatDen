-- Enable Row Level Security
ALTER TABLE user_gym_invoice_applied_discounts ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read applied discounts on their own invoices OR gym staff can read applied discounts from their gyms
CREATE POLICY "Users and gym staff can view applied discounts"
    ON user_gym_invoice_applied_discounts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_invoices inv
            JOIN user_gym_profiles_unfiltered p ON p.crm_user_id = inv.crm_user_id
            WHERE inv.invoice_id = user_gym_invoice_applied_discounts.invoice_id
            AND p.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_invoice_applied_discounts.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_invoice_applied_discounts FROM authenticated;
