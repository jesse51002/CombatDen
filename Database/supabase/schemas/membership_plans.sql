CREATE TABLE membership_plans_unfiltered (
    plan_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_plan_gym REFERENCES gyms(gym_id),
    plan_name VARCHAR NOT NULL CHECK (plan_name <> ''),
    plan_type VARCHAR NOT NULL CHECK (plan_type IN ('trial', 'recurring', 'one_time')),
    class_count INTEGER CHECK (class_count > 0),
    duration_amount INTEGER CHECK (duration_amount > 0),
    duration_unit VARCHAR CHECK (duration_unit IN ('week', 'month', 'year')),
    CONSTRAINT recurring_must_be_monthly
        CHECK (
            plan_type <> 'recurring'
            OR (duration_unit = 'month' AND duration_amount = 1)
        ),
    CONSTRAINT duration_both_or_neither
        CHECK (
            (duration_amount IS NULL) = (duration_unit IS NULL)
        ),
    CONSTRAINT duration_required_unless_class_count
        CHECK (
            (duration_amount IS NOT NULL AND duration_unit IS NOT NULL)
            OR (plan_type <> 'recurring' AND class_count IS NOT NULL)
        ),
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    stripe_product_id VARCHAR,
    -- Waivers a member must sign for this plan: a jsonb array of waiver_id
    -- strings (multi-select; no FK, mirroring gym_classes.allowed_plan_ids).
    waiver_ids JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT chk_plan_waiver_ids_array
        CHECK (jsonb_typeof(waiver_ids) = 'array'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (plan_id),
    UNIQUE (plan_id, gym_id)
);

-- Trigger: plan_type is immutable once set. A plan's billing model
-- (trial / recurring / one_time) is fixed at creation — changing it would
-- break how existing members on the plan are billed. service_role-write-only,
-- so the trigger (which fires for every role) is the real enforcement.
CREATE OR REPLACE FUNCTION prevent_plan_type_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.plan_type IS DISTINCT FROM OLD.plan_type THEN
        RAISE EXCEPTION 'plan_type cannot be changed after creation'
            USING CONSTRAINT = 'plan_type_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_plan_type_overwrite
    BEFORE UPDATE OF plan_type ON membership_plans_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_plan_type_overwrite();

-- View: only exposes plans with a completed Stripe product sync
CREATE VIEW membership_plans
WITH (security_invoker = true)
AS
SELECT * FROM membership_plans_unfiltered
WHERE stripe_product_id IS NOT NULL;

ALTER VIEW membership_plans SET (security_invoker = true);
