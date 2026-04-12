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
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id)
);

-- Partial index: fast webhook lookup by payment intent
CREATE INDEX idx_transactions_stripe_pi
    ON user_gym_transactions (stripe_payment_intent_id)
    WHERE stripe_payment_intent_id IS NOT NULL;
