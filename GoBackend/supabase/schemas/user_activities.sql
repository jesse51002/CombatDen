CREATE TABLE user_activities (
    activity_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    gym_id UUID NOT NULL REFERENCES gyms(gym_id),
    activity_type VARCHAR NOT NULL,
    activity_info JSONB DEFAULT '{}',
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (activity_id),
    CONSTRAINT user_gym
        FOREIGN KEY (user_id, gym_id)
        REFERENCES user_gym_profiles (user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE user_activities ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own activities OR gym owners can read activities from their gyms
CREATE POLICY "Users and gym owners can view activities"
    ON user_activities
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_activities.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Users can insert activities for gyms they belong to
CREATE POLICY "Users can insert activities for their gyms"
    ON user_activities
    FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.user_id = auth.uid()
            AND user_gym_profiles.gym_id = user_activities.gym_id
        )
    );
