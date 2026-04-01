CREATE TABLE gym_rewards (
    reward_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_reward_gym REFERENCES gyms(gym_id),
    title VARCHAR NOT NULL CHECK (title <> ''),
    amount_off VARCHAR,
    image_url VARCHAR,
    point_cost INTEGER NOT NULL CHECK (point_cost > 0),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (reward_id)
);

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
