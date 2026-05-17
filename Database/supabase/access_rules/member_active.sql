ALTER TABLE member_active ENABLE ROW LEVEL SECURITY;

-- Members read their own; gym staff read all rows at their gym.
CREATE POLICY "Users and gym staff can view member active"
    ON member_active
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_active.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_active.gym_id)
    );

CREATE POLICY "Gym staff can insert member active"
    ON member_active
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_active.gym_id));

CREATE POLICY "Gym staff can update member active"
    ON member_active
    FOR UPDATE
    USING (is_gym_admin_or_owner(member_active.gym_id))
    WITH CHECK (is_gym_admin_or_owner(member_active.gym_id));

REVOKE UPDATE (active_id, member_id, gym_id, active_type, created_at)
    ON TABLE member_active FROM authenticated;
