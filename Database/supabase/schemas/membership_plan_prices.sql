CREATE TABLE membership_plan_prices_unfiltered (
    price_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    plan_id UUID NOT NULL CONSTRAINT fk_plan_price_plan REFERENCES membership_plans_unfiltered(plan_id),
    gym_id UUID NOT NULL CONSTRAINT fk_plan_price_gym REFERENCES gyms(gym_id),
    stripe_price_id VARCHAR,
    price INTEGER NOT NULL CHECK (price >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (price_id),
    UNIQUE (price_id, plan_id),
    CONSTRAINT fk_plan_price_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans_unfiltered (plan_id, gym_id)
);

-- At most one active price per plan (0 is allowed, 2+ is rejected)
CREATE UNIQUE INDEX idx_max_one_active_price_per_plan
    ON membership_plan_prices_unfiltered (plan_id) WHERE is_active = TRUE;

-- View: only exposes prices with a completed Stripe price sync
CREATE VIEW membership_plan_prices
WITH (security_invoker = true)
AS
SELECT * FROM membership_plan_prices_unfiltered
WHERE stripe_price_id IS NOT NULL;

ALTER VIEW membership_plan_prices SET (security_invoker = true);
