CREATE TABLE member_memberships (
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    start_date DATE NOT NULL,
    status VARCHAR NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'cancelled')),
    last_paid_date DATE,
    next_due_date DATE,
    discount_ids JSONB,
    custom_discounts JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (crm_user_id, gym_id, plan_id),
    CONSTRAINT fk_membership_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id),
    CONSTRAINT fk_membership_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans (plan_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE member_memberships ENABLE ROW LEVEL SECURITY;

-- Policy: Gym owners can view memberships for their gyms
CREATE POLICY "Gym owners can view memberships"
    ON member_memberships
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = member_memberships.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Members can view their own memberships
CREATE POLICY "Members can view own memberships"
    ON member_memberships
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.crm_user_id = member_memberships.crm_user_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym owners can insert memberships
CREATE POLICY "Gym owners can insert memberships"
    ON member_memberships
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = member_memberships.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Policy: Gym owners can update memberships
CREATE POLICY "Gym owners can update memberships"
    ON member_memberships
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = member_memberships.gym_id
            AND gyms.owner_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = member_memberships.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (crm_user_id, gym_id, plan_id, start_date, created_at) ON TABLE member_memberships FROM authenticated;

-- Trigger: validates that every UUID in discount_ids exists in gym_discounts for the same gym
CREATE OR REPLACE FUNCTION check_discount_ids_gym_match()
RETURNS TRIGGER AS $$
DECLARE
    discount_id_text TEXT;
    discount_uuid UUID;
BEGIN
    IF NEW.discount_ids IS NOT NULL AND jsonb_array_length(NEW.discount_ids) > 0 THEN
        FOR discount_id_text IN SELECT jsonb_array_elements_text(NEW.discount_ids)
        LOOP
            discount_uuid := discount_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM gym_discounts
                WHERE discount_id = discount_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'discount_id % does not belong to gym_id %', discount_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_discount_ids_gym_match
    BEFORE INSERT OR UPDATE OF discount_ids ON member_memberships
    FOR EACH ROW EXECUTE FUNCTION check_discount_ids_gym_match();
