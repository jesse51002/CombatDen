CREATE TABLE user_gym_profiles (
    user_id UUID NOT NULL REFERENCES auth.users(id),
    gym_id UUID NOT NULL REFERENCES gyms(gym_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_class TIMESTAMPTZ,
    rank VARCHAR,
    account_status VARCHAR,
    PRIMARY KEY (user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE user_gym_profiles ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own profile OR gym owners can read profiles from their gyms
CREATE POLICY "Users and gym owners can view profiles"
    ON user_gym_profiles
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_profiles.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Users can update their own profile OR gym owners can update profiles from their gyms
CREATE POLICY "Users and gym owners can update profiles"
    ON user_gym_profiles
    FOR UPDATE
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_profiles.gym_id
            AND gyms.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_profiles.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (user_id, gym_id, created_at) ON TABLE user_gym_profiles FROM authenticated;
