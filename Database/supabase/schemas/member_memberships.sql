CREATE TABLE member_memberships (
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    start_date DATE NOT NULL,
    status VARCHAR NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'cancelled')),
    end_date DATE,
    freeze_start_date DATE,
    freeze_end_date DATE,
    last_paid_date DATE,
    next_due_date DATE,
    discount_ids JSONB,
    total_price FLOAT NOT NULL CHECK (total_price >= 0),
    custom_discounts JSONB,
    account_linked_to_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (crm_user_id, gym_id, plan_id),
    CONSTRAINT fk_membership_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id),
    CONSTRAINT fk_membership_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans (plan_id, gym_id),
    CONSTRAINT fk_membership_linked_account_same_gym
        FOREIGN KEY (account_linked_to_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE member_memberships ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view memberships for their gyms
CREATE POLICY "Gym staff can view memberships"
    ON member_memberships
    FOR SELECT
    USING (is_gym_admin_or_owner(member_memberships.gym_id));

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

-- Policy: Gym staff can insert memberships
CREATE POLICY "Gym staff can insert memberships"
    ON member_memberships
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(member_memberships.gym_id));

-- Policy: Gym staff can update memberships
CREATE POLICY "Gym staff can update memberships"
    ON member_memberships
    FOR UPDATE
    USING (is_gym_admin_or_owner(member_memberships.gym_id))
    WITH CHECK (is_gym_admin_or_owner(member_memberships.gym_id));

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
