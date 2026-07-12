ALTER TABLE gym_video_spec ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's video spec. Defense-in-depth: admin/owner
-- only (tightened from the general is_gym_employee staff check).
CREATE POLICY "Gym employees can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_video_spec.gym_id));

-- Members can view their gym's video spec (member app showcase).
CREATE POLICY "Members can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_spec.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- Append-only, written only by the backend (service_role): the preset import
-- (system_update), the conversational config agent (admin_update), and the
-- feed-learning refiner (feed_update). Clients never write — they read the
-- latest version through the security_invoker `gym_video_spec_latest` view.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_spec FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON gym_video_spec_latest FROM authenticated;
