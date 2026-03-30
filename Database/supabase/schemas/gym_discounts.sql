CREATE TABLE gym_discounts (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off FLOAT CHECK (dollar_off > 0),
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (discount_id),
    CHECK (num_nonnulls(percentage_off, dollar_off) = 1)
);

-- Enable Row Level Security
ALTER TABLE gym_discounts ENABLE ROW LEVEL SECURITY;

-- Policy: Gym owners can view their discounts
CREATE POLICY "Gym owners can view discounts"
    ON gym_discounts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_discounts.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Gym owners can insert discounts
CREATE POLICY "Gym owners can insert discounts"
    ON gym_discounts
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_discounts.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Gym owners can update their discounts
CREATE POLICY "Gym owners can update discounts"
    ON gym_discounts
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_discounts.gym_id
            AND gyms.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_discounts.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (discount_id, gym_id, created_at) ON TABLE gym_discounts FROM authenticated;
