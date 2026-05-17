ALTER TABLE member_attendance ENABLE ROW LEVEL SECURITY;

-- Members can read their own attendance; gym staff can read everything at their gym
CREATE POLICY "Users and gym staff can view attendance"
    ON member_attendance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_attendance.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_attendance.gym_id)
    );

CREATE POLICY "Gym staff can insert attendance"
    ON member_attendance
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_attendance.gym_id));

-- Append-only
REVOKE UPDATE ON TABLE member_attendance FROM authenticated;
