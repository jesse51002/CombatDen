ALTER TABLE member_video_profile ENABLE ROW LEVEL SECURITY;

-- A member can read their own profile rows; gym staff can read their gym's.
CREATE POLICY "Members and gym staff can view video profiles"
    ON member_video_profile
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_video_profile.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_video_profile.gym_id)
    );

-- Built/refreshed by the backend (service_role) only — profile text +
-- embedding are derived artifacts, never client-written.
REVOKE INSERT, UPDATE, DELETE ON TABLE member_video_profile FROM authenticated;
