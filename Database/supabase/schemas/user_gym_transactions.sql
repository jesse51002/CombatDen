CREATE TABLE user_gym_transactions (
    transaction_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_transaction_gym REFERENCES gyms(gym_id),
    item_id UUID NOT NULL,
    amount_paid INTEGER NOT NULL CHECK (amount_paid >= 0),
    item_type VARCHAR,
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_discounts JSONB,
    stripe_payment_intent_id VARCHAR,
    stripe_invoice_id VARCHAR,
    extra_info JSONB DEFAULT '{}',
    PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transaction_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE user_gym_transactions ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own transactions OR gym staff can read transactions from their gyms
CREATE POLICY "Users and gym staff can view transactions"
    ON user_gym_transactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = user_gym_transactions.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(user_gym_transactions.gym_id)
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE user_gym_transactions FROM authenticated;

-- Partial index: fast webhook lookup by payment intent
CREATE INDEX idx_transactions_stripe_pi
    ON user_gym_transactions (stripe_payment_intent_id)
    WHERE stripe_payment_intent_id IS NOT NULL;
