CREATE TABLE gyms (
    gym_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_name VARCHAR NOT NULL CHECK (gym_name <> ''),
    owner_id UUID NOT NULL UNIQUE
        CONSTRAINT fk_gyms_owner REFERENCES auth.users(id),
    rank_enabled BOOLEAN NOT NULL DEFAULT true,
    rank_preset VARCHAR CHECK (rank_preset IN ('bjj', 'muay_thai', 'karate', 'taekwondo', 'judo', 'mma')),
    rank_1_name VARCHAR,
    rank_2_name VARCHAR,
    rank_3_name VARCHAR,
    rank_4_name VARCHAR,
    rank_5_name VARCHAR,
    estimated_classes_rank_1 INTEGER NOT NULL CHECK (estimated_classes_rank_1 >= 0) DEFAULT 20,
    estimated_classes_rank_2 INTEGER NOT NULL CHECK (estimated_classes_rank_2 >= 0) DEFAULT 100,
    estimated_classes_rank_3 INTEGER NOT NULL CHECK (estimated_classes_rank_3 >= 0) DEFAULT 200,
    estimated_classes_rank_4 INTEGER NOT NULL CHECK (estimated_classes_rank_4 >= 0) DEFAULT 200,
    estimated_classes_rank_5 INTEGER NOT NULL CHECK (estimated_classes_rank_5 >= 0) DEFAULT 200,
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

-- Policy: Owners can insert their own gyms
CREATE POLICY "Owners can insert their own gyms"
    ON gyms
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = owner_id);

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (owner_id, gym_id) ON TABLE gyms FROM authenticated;
