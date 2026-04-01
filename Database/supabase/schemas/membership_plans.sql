CREATE TABLE membership_plans (
    plan_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_plan_gym REFERENCES gyms(gym_id),
    plan_name VARCHAR NOT NULL CHECK (plan_name <> ''),
    plan_type VARCHAR NOT NULL CHECK (plan_type IN ('trial', 'recurring', 'one_time')),
    base_cost FLOAT NOT NULL CHECK (base_cost >= 0),
    additional_member_costs JSONB,
    class_count INTEGER CHECK (class_count > 0),
    duration_amount INTEGER NOT NULL CHECK (duration_amount > 0),
    duration_unit VARCHAR NOT NULL CHECK (duration_unit IN ('week', 'month', 'year')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (plan_id),
    UNIQUE (plan_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE membership_plans ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their plans
CREATE POLICY "Gym staff can view plans"
    ON membership_plans
    FOR SELECT
    USING (is_gym_admin_or_owner(membership_plans.gym_id));

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

-- Policy: Gym staff can insert plans
CREATE POLICY "Gym staff can insert plans"
    ON membership_plans
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(membership_plans.gym_id));

-- Policy: Gym staff can update their plans
CREATE POLICY "Gym staff can update plans"
    ON membership_plans
    FOR UPDATE
    USING (is_gym_admin_or_owner(membership_plans.gym_id))
    WITH CHECK (is_gym_admin_or_owner(membership_plans.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (plan_id, gym_id, created_at) ON TABLE membership_plans FROM authenticated;
