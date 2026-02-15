CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_name VARCHAR,
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    PRIMARY KEY (gym_id)
);

-- Enable Row Level Security
ALTER TABLE gyms ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own data
CREATE POLICY "Users can view own data"
    ON gyms
    FOR SELECT
    USING (auth.uid() = owner_id);

-- Policy: Users can update their own data
CREATE POLICY "Users can update own data"
    ON gyms
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (owner_id, gym_id) ON TABLE gyms FROM authenticated;
