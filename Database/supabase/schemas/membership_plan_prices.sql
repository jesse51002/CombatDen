CREATE TABLE membership_plan_prices (
    price_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    plan_id UUID NOT NULL CONSTRAINT fk_plan_price_plan REFERENCES membership_plans(plan_id),
    gym_id UUID NOT NULL CONSTRAINT fk_plan_price_gym REFERENCES gyms(gym_id),
    stripe_price_id VARCHAR,
    price INTEGER NOT NULL CHECK (price >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (price_id),
    UNIQUE (price_id, plan_id),
    CONSTRAINT fk_plan_price_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans (plan_id, gym_id)
);

-- At most one active price per plan (0 is allowed, 2+ is rejected)
CREATE UNIQUE INDEX idx_max_one_active_price_per_plan
    ON membership_plan_prices (plan_id) WHERE is_active = TRUE;

-- Enable Row Level Security
ALTER TABLE membership_plan_prices ENABLE ROW LEVEL SECURITY;

-- SELECT only (stripe rule: no INSERT/UPDATE for authenticated)
CREATE POLICY "Gym staff can view plan prices"
    ON membership_plan_prices
    FOR SELECT
    USING (is_gym_admin_or_owner(membership_plan_prices.gym_id));

CREATE POLICY "Members can view plan prices"
    ON membership_plan_prices
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = membership_plan_prices.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE membership_plan_prices FROM authenticated;
