ALTER TABLE gym_video_feed ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's feed.
CREATE POLICY "Gym employees can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (is_gym_employee(gym_video_feed.gym_id));

-- Members can view their gym's feed (member app video surfaces).
CREATE POLICY "Members can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_feed.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_feed FROM authenticated;
