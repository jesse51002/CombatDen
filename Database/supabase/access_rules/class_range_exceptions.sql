ALTER TABLE class_range_exceptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view range exceptions"
    ON class_range_exceptions
    FOR SELECT
    USING (is_gym_employee(class_range_exceptions.gym_id));

CREATE POLICY "Members can view range exceptions"
    ON class_range_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_range_exceptions.gym_id
            AND members.user_id = auth.uid()
        )
    );

CREATE POLICY "Gym staff can insert range exceptions"
    ON class_range_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(class_range_exceptions.gym_id));

CREATE POLICY "Gym staff can update range exceptions"
    ON class_range_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(class_range_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(class_range_exceptions.gym_id));

REVOKE UPDATE (exception_id, class_id, gym_id, created_at)
    ON TABLE class_range_exceptions FROM authenticated;
