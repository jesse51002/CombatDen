-- Enable Row Level Security
ALTER TABLE member_charges ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own charges OR gym staff can read charges from their gyms
CREATE POLICY "Users and gym staff can view charges"
    ON member_charges
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_charges.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_charges.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE member_charges FROM authenticated;
