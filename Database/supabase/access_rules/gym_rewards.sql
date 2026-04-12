-- Enable Row Level Security
ALTER TABLE gym_rewards ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their rewards
CREATE POLICY "Gym staff can view rewards"
    ON gym_rewards
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_rewards.gym_id));

-- Policy: Members can view active rewards for their gym
CREATE POLICY "Members can view active rewards"
    ON gym_rewards
    FOR SELECT
    USING (
        is_active = true
        AND EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_rewards.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert rewards
CREATE POLICY "Gym staff can insert rewards"
    ON gym_rewards
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_rewards.gym_id));

-- Policy: Gym staff can update their rewards
CREATE POLICY "Gym staff can update rewards"
    ON gym_rewards
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_rewards.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_rewards.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (reward_id, gym_id, created_at) ON TABLE gym_rewards FROM authenticated;
