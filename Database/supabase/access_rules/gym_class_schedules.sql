ALTER TABLE gym_class_schedules ENABLE ROW LEVEL SECURITY;

-- Read posture mirrors gym_classes: staff see their gym's schedule versions,
-- members see their gym's (the mobile app renders the schedule).
CREATE POLICY "Gym employees can view class schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (is_gym_employee(gym_class_schedules.gym_id));

CREATE POLICY "Members can view class schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_class_schedules.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- Append-only versioned rows, written by the service-role backend ONLY.
-- Minting a version runs inside one backend transaction with the
-- version-change wipe (sign-up deletion + check-in reversal + points
-- clawback) -- a raw client INSERT would bypass exactly that billing-adjacent
-- logic, the same argument that gates membership_plan_prices /
-- gym_discount_values. No authenticated write path at all; versions are
-- never UPDATE'd or DELETE'd by anyone (write-once rows).
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_class_schedules FROM authenticated;
