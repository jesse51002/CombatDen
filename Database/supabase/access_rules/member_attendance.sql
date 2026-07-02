ALTER TABLE member_attendance ENABLE ROW LEVEL SECURITY;

-- Members can read their own attendance; gym staff can read everything at their gym
CREATE POLICY "Users and gym staff can view attendance"
    ON member_attendance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_attendance.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_attendance.gym_id)
    );

-- Append-only AND written by the service-role backend ONLY (the check-in gate).
-- No authenticated write path at all: staff never insert attendance directly —
-- every write goes through the gated check-in endpoint, so a raw client INSERT
-- can't bypass the eligibility / capacity / points / billing-attribution logic.
REVOKE INSERT, UPDATE, DELETE ON TABLE member_attendance FROM authenticated;
