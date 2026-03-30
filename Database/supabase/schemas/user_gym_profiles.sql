CREATE TABLE user_gym_profiles (
    crm_user_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_profile_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_profile_gym REFERENCES gyms(gym_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_class TIMESTAMPTZ,
    account_status VARCHAR,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    photo_url VARCHAR,
    phone VARCHAR,
    email VARCHAR,
    address VARCHAR,
    emergency_contact_name VARCHAR,
    emergency_contact_phone VARCHAR,
    emergency_contact_email VARCHAR,
    current_rank INTEGER CHECK (current_rank IS NULL OR (current_rank BETWEEN 1 AND 5)),
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    account_linked_to_id UUID,
    PRIMARY KEY (crm_user_id),
    UNIQUE (crm_user_id, gym_id),
    UNIQUE (user_id, gym_id),
    CONSTRAINT fk_profile_linked_account_same_gym
        FOREIGN KEY (account_linked_to_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id)
);

-- Partial unique index: a user can only have one profile per gym
CREATE UNIQUE INDEX unique_user_gym
    ON user_gym_profiles (user_id, gym_id)
    WHERE user_id IS NOT NULL;

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

-- Policy: Gym owners can insert profiles for their gyms
CREATE POLICY "Gym owners can insert profiles"
    ON user_gym_profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_profiles.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (crm_user_id, gym_id, created_at) ON TABLE user_gym_profiles FROM authenticated;

-- Trigger: once user_id is set, it cannot be changed to a different value
CREATE OR REPLACE FUNCTION prevent_user_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_user_id_overwrite
    BEFORE UPDATE OF user_id ON user_gym_profiles
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_overwrite();
