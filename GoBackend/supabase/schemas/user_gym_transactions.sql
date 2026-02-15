CREATE TABLE user_gym_transactions (
    transaction_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    gym_id UUID NOT NULL REFERENCES gyms(gym_id),
    item_id UUID NOT NULL,
    amount_paid FLOAT NOT NULL,
    item_type VARCHAR,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_discounts JSONB,
    extra_info JSONB DEFAULT '{}',
    PRIMARY KEY (transaction_id),
    CONSTRAINT user_gym
        FOREIGN KEY (user_id, gym_id)
        REFERENCES user_gym_profiles (user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE user_gym_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own transactions OR gym owners can read transactions from their gyms
CREATE POLICY "Users and gym owners can view transactions"
    ON user_gym_transactions
    FOR SELECT
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_transactions.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );
