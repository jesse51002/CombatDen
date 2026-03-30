CREATE TABLE membership_plans (
    plan_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_plan_gym REFERENCES gyms(gym_id),
    plan_name VARCHAR NOT NULL CHECK (plan_name <> ''),
    plan_type VARCHAR,
    base_cost FLOAT NOT NULL CHECK (base_cost >= 0),
    additional_member_costs JSONB,
    billing_cycle VARCHAR NOT NULL CHECK (billing_cycle <> ''),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (plan_id),
    UNIQUE (plan_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE membership_plans ENABLE ROW LEVEL SECURITY;

-- Policy: Gym owners can view their plans
CREATE POLICY "Gym owners can view plans"
    ON membership_plans
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = membership_plans.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Members can view plans for their gym
CREATE POLICY "Members can view gym plans"
    ON membership_plans
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = membership_plans.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym owners can insert plans
CREATE POLICY "Gym owners can insert plans"
    ON membership_plans
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = membership_plans.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Gym owners can update their plans
CREATE POLICY "Gym owners can update plans"
    ON membership_plans
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = membership_plans.gym_id
            AND gyms.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = membership_plans.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (plan_id, gym_id, created_at) ON TABLE membership_plans FROM authenticated;
