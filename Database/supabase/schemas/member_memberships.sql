CREATE TABLE member_memberships (
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    price_id UUID NOT NULL CONSTRAINT fk_membership_price REFERENCES membership_plan_prices(price_id),
    start_date DATE NOT NULL,
    end_date DATE,
    cancel_date DATE,
    freeze_start_date DATE,
    freeze_end_date DATE,
    last_paid_date DATE,
    next_due_date DATE,
    discount_ids JSONB,
    stripe_item_id VARCHAR,
    prorate BOOLEAN NOT NULL DEFAULT true,
    total_price INTEGER NOT NULL CHECK (total_price >= 0),
    price_formula VARCHAR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (crm_user_id, gym_id, plan_id),
    CONSTRAINT fk_membership_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles (crm_user_id, gym_id),
    CONSTRAINT fk_membership_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans (plan_id, gym_id),
    CONSTRAINT fk_membership_price_plan
        FOREIGN KEY (price_id, plan_id)
        REFERENCES membership_plan_prices (price_id, plan_id)
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

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE ON TABLE member_memberships FROM authenticated;

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

-- Trigger: recurring plans cannot have an end_date
CREATE OR REPLACE FUNCTION check_recurring_no_end_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.end_date IS NOT NULL THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships cannot have an end_date'
                USING CONSTRAINT = 'recurring_no_end_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_no_end_date
    BEFORE INSERT OR UPDATE OF end_date ON member_memberships
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_end_date();

-- View: derives status from date fields (cancel_date > end_date > freeze window > active)
CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT *,
    CASE
        WHEN cancel_date IS NOT NULL AND cancel_date <= CURRENT_DATE THEN 'cancelled'
        WHEN end_date IS NOT NULL AND end_date <= CURRENT_DATE THEN 'ended'
        WHEN freeze_start_date IS NOT NULL
             AND freeze_end_date IS NOT NULL
             AND freeze_start_date <= CURRENT_DATE
             AND CURRENT_DATE <= freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);
