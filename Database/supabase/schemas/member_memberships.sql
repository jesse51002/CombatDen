-- Memberships are append-only: once created, a membership can only be
-- cancelled (cancel_date set), never modified back to active. To start
-- a new membership the client must INSERT a new row with a different
-- primary key (crm_user_id, gym_id, plan_id).
CREATE TABLE member_memberships_unfiltered (
    item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    crm_user_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    price_id UUID NOT NULL CONSTRAINT fk_membership_price REFERENCES membership_plan_prices_unfiltered(price_id),
    start_date DATE NOT NULL,
    end_date DATE,
    cancel_date DATE,
    last_paid_date DATE,
    next_due_date DATE,
    discount_ids JSONB,
    stripe_item_id VARCHAR,
    prorate BOOLEAN NOT NULL DEFAULT true,
    total_price INTEGER NOT NULL CHECK (total_price >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id),
    UNIQUE (item_id, crm_user_id),
    CONSTRAINT fk_membership_profile_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id),
    CONSTRAINT fk_membership_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans_unfiltered (plan_id, gym_id),
    CONSTRAINT fk_membership_price_plan
        FOREIGN KEY (price_id, plan_id)
        REFERENCES membership_plan_prices_unfiltered (price_id, plan_id)
);

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
                SELECT 1 FROM gym_discounts_unfiltered
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
    BEFORE INSERT OR UPDATE OF discount_ids ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_discount_ids_gym_match();

-- Trigger: plan_id is immutable once set
CREATE OR REPLACE FUNCTION prevent_plan_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
        RAISE EXCEPTION 'plan_id cannot be changed after creation'
            USING CONSTRAINT = 'plan_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_plan_id_overwrite
    BEFORE UPDATE OF plan_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_plan_id_overwrite();

-- Trigger: cancel_date is immutable once set
CREATE OR REPLACE FUNCTION prevent_cancel_date_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.cancel_date IS NOT NULL AND NEW.cancel_date IS DISTINCT FROM OLD.cancel_date THEN
        RAISE EXCEPTION 'cancel_date cannot be changed once set'
            USING CONSTRAINT = 'cancel_date_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_cancel_date_overwrite
    BEFORE UPDATE OF cancel_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_cancel_date_overwrite();

-- Trigger: stripe_item_id is immutable
CREATE OR REPLACE FUNCTION prevent_stripe_item_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_item_id IS NOT NULL AND NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_stripe_item_id_overwrite
    BEFORE UPDATE OF stripe_item_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_stripe_item_id_overwrite();

-- Trigger: recurring plans cannot have an end_date
CREATE OR REPLACE FUNCTION check_recurring_no_end_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.end_date IS NOT NULL THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans_unfiltered
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
    BEFORE INSERT OR UPDATE OF end_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_end_date();

-- Trigger: inserting a recurring membership requires all existing memberships
-- for the same user+gym to be ended or cancelled
CREATE OR REPLACE FUNCTION check_recurring_no_active_memberships()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_active_count INTEGER;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT COUNT(*) INTO v_active_count
        FROM member_memberships_unfiltered mm
        WHERE mm.crm_user_id = NEW.crm_user_id
          AND mm.gym_id = NEW.gym_id
          AND mm.item_id <> NEW.item_id
          AND (mm.cancel_date IS NULL OR mm.cancel_date > CURRENT_DATE)
          AND (mm.end_date IS NULL OR mm.end_date > CURRENT_DATE);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while active memberships exist'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_no_active_memberships
    BEFORE INSERT ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_active_memberships();

-- Trigger: no overlapping date ranges for recurring memberships on the same plan
CREATE OR REPLACE FUNCTION check_recurring_no_overlapping_daterange()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships_unfiltered mm
            WHERE mm.crm_user_id = NEW.crm_user_id
              AND mm.gym_id = NEW.gym_id
              AND mm.plan_id = NEW.plan_id
              AND mm.item_id <> NEW.item_id
              AND daterange(mm.start_date, mm.cancel_date, '[)')
               && daterange(NEW.start_date, NEW.cancel_date, '[)')
        ) THEN
            RAISE EXCEPTION 'recurring membership overlaps an existing membership on the same plan'
                USING CONSTRAINT = 'recurring_no_overlapping_daterange';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_no_overlapping_daterange
    BEFORE INSERT OR UPDATE OF cancel_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_overlapping_daterange();

-- Trigger: new recurring memberships must have a start_date strictly after
-- all previous entries for the same (crm_user_id, gym_id, plan_id)
CREATE OR REPLACE FUNCTION check_recurring_chronological_start_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_max_start_date DATE;
BEGIN
    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships_unfiltered mm
        WHERE mm.crm_user_id = NEW.crm_user_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id;

        IF v_max_start_date IS NOT NULL AND NEW.start_date <= v_max_start_date THEN
            RAISE EXCEPTION 'start_date must be after % (latest existing start_date for this plan)', v_max_start_date
                USING CONSTRAINT = 'recurring_chronological_start_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_chronological_start_date
    BEFORE INSERT ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_chronological_start_date();

-- View: only exposes memberships with a completed Stripe item sync
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL;

ALTER VIEW member_memberships SET (security_invoker = true);

-- View: derives status from date fields (cancel_date > end_date > account freeze window > active)
-- Linked (child) accounts inherit freeze from their parent account.
CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= CURRENT_DATE THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= CURRENT_DATE THEN 'ended'
        WHEN freeze_owner.freeze_start_date IS NOT NULL
             AND freeze_owner.freeze_end_date IS NOT NULL
             AND freeze_owner.freeze_start_date <= CURRENT_DATE
             AND CURRENT_DATE <= freeze_owner.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN user_gym_profiles_unfiltered ugp
    ON ugp.crm_user_id = mm.crm_user_id
JOIN user_gym_profiles_unfiltered freeze_owner
    ON freeze_owner.crm_user_id = COALESCE(ugp.account_linked_to_id, ugp.crm_user_id);

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);
