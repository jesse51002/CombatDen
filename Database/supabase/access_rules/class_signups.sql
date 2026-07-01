ALTER TABLE class_signups ENABLE ROW LEVEL SECURITY;

-- Members can read their own sign-ups; gym staff can read everything at their
-- gym. Mirrors member_attendance's SELECT policy shape.
CREATE POLICY "Users and gym staff can view class signups"
    ON class_signups
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = class_signups.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(class_signups.gym_id)
    );

-- Both staff and the member themselves may create / cancel a sign-up, but
-- that authorization (staff-for-any-gym-member OR member-for-self) is
-- enforced by the API's verify_can_view_member check, not by RLS --
-- class_signups has NO authenticated write policy at all: every write goes
-- through the backend's service_role connection.
REVOKE INSERT, UPDATE, DELETE ON TABLE class_signups FROM authenticated;
