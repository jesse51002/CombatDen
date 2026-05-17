ALTER TABLE class_history ENABLE ROW LEVEL SECURITY;

-- Members can see history for their gym; staff see all
CREATE POLICY "Users and gym staff can view class history"
    ON class_history
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_history.gym_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(class_history.gym_id)
    );

CREATE POLICY "Gym staff can insert class history"
    ON class_history
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(class_history.gym_id));

-- Append-only — no UPDATE for authenticated users
REVOKE UPDATE ON TABLE class_history FROM authenticated;
