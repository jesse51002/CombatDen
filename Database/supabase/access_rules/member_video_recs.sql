ALTER TABLE member_video_recs ENABLE ROW LEVEL SECURITY;

-- A member can read their own rec history; gym staff can read their gym's.
CREATE POLICY "Members and gym staff can view rec history"
    ON member_video_recs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_video_recs.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_video_recs.gym_id)
    );

-- Recorded by the backend (service_role) when a recommendation is served;
-- clients never write rec history.
REVOKE INSERT, UPDATE, DELETE ON TABLE member_video_recs FROM authenticated;
