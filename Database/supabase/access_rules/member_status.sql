ALTER TABLE member_status ENABLE ROW LEVEL SECURITY;

-- Members read their own; gym staff read all rows at their gym.
CREATE POLICY "Users and gym staff can view account status"
    ON member_status
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_status.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_status.gym_id)
    );

CREATE POLICY "Gym staff can insert account status"
    ON member_status
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_status.gym_id));

CREATE POLICY "Gym staff can update account status"
    ON member_status
    FOR UPDATE
    USING (is_gym_admin_or_owner(member_status.gym_id))
    WITH CHECK (is_gym_admin_or_owner(member_status.gym_id));

REVOKE UPDATE (status_id, member_id, gym_id, status_type, created_at)
    ON TABLE member_status FROM authenticated;
