CREATE TABLE user_gym_transactions (
    transaction_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_transaction_gym REFERENCES gyms(gym_id),
    item_id UUID NOT NULL,
    amount_paid FLOAT NOT NULL,
    item_type VARCHAR,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_discounts JSONB,
    extra_info JSONB DEFAULT '{}',
    PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transaction_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE user_gym_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own transactions OR gym owners can read transactions from their gyms
CREATE POLICY "Users and gym owners can view transactions"
    ON user_gym_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_transactions.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Gym owners can insert transactions for their gyms
CREATE POLICY "Gym owners can insert transactions"
    ON user_gym_transactions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = user_gym_transactions.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (transaction_id, crm_user_id, gym_id, time) ON TABLE user_gym_transactions FROM authenticated;
