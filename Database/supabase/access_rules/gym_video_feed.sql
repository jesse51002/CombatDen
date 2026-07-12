ALTER TABLE gym_video_feed ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's feed. Defense-in-depth: admin/owner only
-- (tightened from the general is_gym_employee staff check).
CREATE POLICY "Gym employees can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_video_feed.gym_id));

-- Members can view their gym's feed (member app video surfaces).
CREATE POLICY "Members can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_feed.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_feed FROM authenticated;
