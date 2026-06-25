ALTER TABLE gym_video_spec ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's video spec.
CREATE POLICY "Gym employees can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (is_gym_employee(gym_video_spec.gym_id));

-- Members can view their gym's video spec (member app showcase).
CREATE POLICY "Members can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_spec.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_spec FROM authenticated;
