ALTER TABLE member_activities ENABLE ROW LEVEL SECURITY;

-- Members read their own activities; gym staff read everything at their gym
CREATE POLICY "Users and gym staff can view activities"
    ON member_activities
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_activities.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_activities.gym_id)
    );

CREATE POLICY "Gym staff can insert activities"
    ON member_activities
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_activities.gym_id));

-- Append-only
REVOKE UPDATE ON TABLE member_activities FROM authenticated;
