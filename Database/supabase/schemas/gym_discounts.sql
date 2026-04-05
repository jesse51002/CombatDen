CREATE TABLE gym_discounts (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    discount_type VARCHAR NOT NULL CHECK (discount_type IN ('membership', 'custom')),
    discount_active BOOLEAN NOT NULL DEFAULT true,
    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off FLOAT CHECK (dollar_off > 0),
    end_date DATE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    stripe_coupon_id VARCHAR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (discount_id),
    CHECK (num_nonnulls(percentage_off, dollar_off) = 1)
);

-- Enable Row Level Security
ALTER TABLE gym_discounts ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their discounts
CREATE POLICY "Gym staff can view discounts"
    ON gym_discounts
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_discounts.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE ON TABLE gym_discounts FROM authenticated;
