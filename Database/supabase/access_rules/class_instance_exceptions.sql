ALTER TABLE class_instance_exceptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view instance exceptions"
    ON class_instance_exceptions
    FOR SELECT
    USING (is_gym_employee(class_instance_exceptions.gym_id));

CREATE POLICY "Members can view instance exceptions"
    ON class_instance_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_instance_exceptions.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

CREATE POLICY "Gym staff can insert instance exceptions"
    ON class_instance_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(class_instance_exceptions.gym_id));

CREATE POLICY "Gym staff can update instance exceptions"
    ON class_instance_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(class_instance_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(class_instance_exceptions.gym_id));

REVOKE UPDATE (exception_id, class_id, gym_id, original_date, original_time,
               created_at)
    ON TABLE class_instance_exceptions FROM authenticated;
