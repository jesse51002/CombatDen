-- Enable Row Level Security
ALTER TABLE member_charges ENABLE ROW LEVEL SECURITY;

-- Policy: a member reads a charge they PAID (paid_by_member_id) or whose invoice
-- was FOR them (their id is in the invoice's paid_for); gym staff read their
-- gym's charges. paid_for lives on the invoice, so the beneficiary arm joins it.
CREATE POLICY "Users and gym staff can view charges"
    ON member_charges
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_charges.paid_by_member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON lower(m.email) = lower(auth.jwt() ->> 'email')
            WHERE inv.invoice_id = member_charges.invoice_id
            AND inv.paid_for ? m.member_id::text
        )
        OR is_gym_admin_or_owner(member_charges.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_charges FROM authenticated;
