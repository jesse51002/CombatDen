ALTER TABLE member_reward_redemptions ENABLE ROW LEVEL SECURITY;

-- Members see their own; staff see everything at their gym
CREATE POLICY "Users and gym staff can view reward redemptions"
    ON member_reward_redemptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_reward_redemptions.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_reward_redemptions.gym_id)
    );

-- Members can redeem their own rewards; staff can record redemptions for anyone at their gym
CREATE POLICY "Members and gym staff can insert redemptions"
    ON member_reward_redemptions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        is_gym_admin_or_owner(member_reward_redemptions.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_reward_redemptions.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
            AND members.gym_id = member_reward_redemptions.gym_id
        )
    );

-- Append-only
REVOKE UPDATE ON TABLE member_reward_redemptions FROM authenticated;
