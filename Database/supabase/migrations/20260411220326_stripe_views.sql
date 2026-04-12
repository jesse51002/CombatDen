-- ============================================================
-- DB-First Stripe Writes: Rename tables to _unfiltered, create filtered views
-- Uses ALTER TABLE RENAME to preserve data and FK integrity
-- ============================================================

-- Phase 1: Drop dependent views
DROP VIEW IF EXISTS member_memberships_status;

-- Phase 2: Rename tables (preserves data, indexes, constraints, triggers)
ALTER TABLE membership_plans RENAME TO membership_plans_unfiltered;
ALTER TABLE membership_plan_prices RENAME TO membership_plan_prices_unfiltered;
ALTER TABLE gym_discounts RENAME TO gym_discounts_unfiltered;
ALTER TABLE user_gym_profiles RENAME TO user_gym_profiles_unfiltered;
ALTER TABLE member_memberships RENAME TO member_memberships_unfiltered;

-- Phase 2.5: Rename auto-generated constraints and indexes
-- (ALTER TABLE RENAME preserves data but keeps old constraint/index names)

-- membership_plans_unfiltered
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_pkey TO membership_plans_unfiltered_pkey;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_plan_id_gym_id_key TO membership_plans_unfiltered_plan_id_gym_id_key;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_plan_name_check TO membership_plans_unfiltered_plan_name_check;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_plan_type_check TO membership_plans_unfiltered_plan_type_check;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_class_count_check TO membership_plans_unfiltered_class_count_check;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_duration_amount_check TO membership_plans_unfiltered_duration_amount_check;
ALTER TABLE membership_plans_unfiltered RENAME CONSTRAINT membership_plans_duration_unit_check TO membership_plans_unfiltered_duration_unit_check;

-- membership_plan_prices_unfiltered
ALTER TABLE membership_plan_prices_unfiltered RENAME CONSTRAINT membership_plan_prices_pkey TO membership_plan_prices_unfiltered_pkey;
ALTER TABLE membership_plan_prices_unfiltered RENAME CONSTRAINT membership_plan_prices_price_id_plan_id_key TO membership_plan_prices_unfiltered_price_id_plan_id_key;
ALTER TABLE membership_plan_prices_unfiltered RENAME CONSTRAINT membership_plan_prices_price_check TO membership_plan_prices_unfiltered_price_check;

-- gym_discounts_unfiltered
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_pkey TO gym_discounts_unfiltered_pkey;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_discount_id_gym_id_key TO gym_discounts_unfiltered_discount_id_gym_id_key;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_check TO gym_discounts_unfiltered_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_discount_name_check TO gym_discounts_unfiltered_discount_name_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_discount_type_check TO gym_discounts_unfiltered_discount_type_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_percentage_off_check TO gym_discounts_unfiltered_percentage_off_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_dollar_off_check TO gym_discounts_unfiltered_dollar_off_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_linked_discount_num_check TO gym_discounts_unfiltered_linked_discount_num_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_duration_check TO gym_discounts_unfiltered_duration_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_duration_in_months_check TO gym_discounts_unfiltered_duration_in_months_check;
ALTER TABLE gym_discounts_unfiltered RENAME CONSTRAINT gym_discounts_gym_id_membership_plan_id_linked_discount_num_key TO gym_discounts_unfiltered_gym_id_membership_plan_id_linked_d_key;

-- user_gym_profiles_unfiltered
ALTER TABLE user_gym_profiles_unfiltered RENAME CONSTRAINT user_gym_profiles_pkey TO user_gym_profiles_unfiltered_pkey;
ALTER TABLE user_gym_profiles_unfiltered RENAME CONSTRAINT user_gym_profiles_crm_user_id_gym_id_key TO user_gym_profiles_unfiltered_crm_user_id_gym_id_key;
ALTER TABLE user_gym_profiles_unfiltered RENAME CONSTRAINT user_gym_profiles_first_name_check TO user_gym_profiles_unfiltered_first_name_check;
ALTER TABLE user_gym_profiles_unfiltered RENAME CONSTRAINT user_gym_profiles_last_name_check TO user_gym_profiles_unfiltered_last_name_check;
ALTER TABLE user_gym_profiles_unfiltered RENAME CONSTRAINT user_gym_profiles_points_balance_check TO user_gym_profiles_unfiltered_points_balance_check;

-- member_memberships_unfiltered
ALTER TABLE member_memberships_unfiltered RENAME CONSTRAINT member_memberships_pkey TO member_memberships_unfiltered_pkey;
ALTER TABLE member_memberships_unfiltered RENAME CONSTRAINT member_memberships_item_id_crm_user_id_key TO member_memberships_unfiltered_item_id_crm_user_id_key;
ALTER TABLE member_memberships_unfiltered RENAME CONSTRAINT member_memberships_total_price_check TO member_memberships_unfiltered_total_price_check;

-- Phase 3: Make stripe columns nullable
ALTER TABLE membership_plan_prices_unfiltered ALTER COLUMN stripe_price_id DROP NOT NULL;
ALTER TABLE user_gym_profiles_unfiltered ALTER COLUMN stripe_customer_id DROP NOT NULL;
ALTER TABLE member_memberships_unfiltered ALTER COLUMN stripe_item_id DROP NOT NULL;

-- Phase 4: Create filtered views (original table names become views)
CREATE VIEW membership_plans WITH (security_invoker = true) AS
SELECT * FROM membership_plans_unfiltered WHERE stripe_product_id IS NOT NULL;
ALTER VIEW membership_plans SET (security_invoker = true);

CREATE VIEW membership_plan_prices WITH (security_invoker = true) AS
SELECT * FROM membership_plan_prices_unfiltered WHERE stripe_price_id IS NOT NULL;
ALTER VIEW membership_plan_prices SET (security_invoker = true);

CREATE VIEW gym_discounts WITH (security_invoker = true) AS
SELECT * FROM gym_discounts_unfiltered WHERE stripe_coupon_id IS NOT NULL;
ALTER VIEW gym_discounts SET (security_invoker = true);

CREATE VIEW user_gym_profiles WITH (security_invoker = true) AS
SELECT * FROM user_gym_profiles_unfiltered WHERE stripe_customer_id IS NOT NULL;
ALTER VIEW user_gym_profiles SET (security_invoker = true);

CREATE VIEW member_memberships WITH (security_invoker = true) AS
SELECT * FROM member_memberships_unfiltered WHERE stripe_item_id IS NOT NULL;
ALTER VIEW member_memberships SET (security_invoker = true);

-- Phase 5: Recreate member_memberships_status view
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
ALTER VIEW member_memberships_status SET (security_invoker = true);

-- Phase 6: Update trigger functions (must query _unfiltered tables for constraint validation)

CREATE OR REPLACE FUNCTION check_class_plan_ids_gym_match()
RETURNS TRIGGER AS $$
DECLARE
    plan_id_text TEXT;
    plan_uuid UUID;
BEGIN
    IF NEW.allowed_plan_ids IS NOT NULL AND jsonb_array_length(NEW.allowed_plan_ids) > 0 THEN
        FOR plan_id_text IN SELECT jsonb_array_elements_text(NEW.allowed_plan_ids)
        LOOP
            plan_uuid := plan_id_text::UUID;
            IF NOT EXISTS (
                SELECT 1 FROM membership_plans_unfiltered
                WHERE plan_id = plan_uuid
                AND gym_id = NEW.gym_id
            ) THEN
                RAISE EXCEPTION 'plan_id % does not belong to gym_id %', plan_uuid, NEW.gym_id;
            END IF;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_linked_discount_sequence()
RETURNS TRIGGER AS $$
DECLARE
    max_num INTEGER;
    total_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts_unfiltered
        WHERE gym_id = NEW.gym_id
          AND membership_plan_id = NEW.membership_plan_id
          AND discount_type = 'linked';

        IF NEW.linked_discount_num <> max_num + 1 THEN
            RAISE EXCEPTION 'linked_discount_num must be % (next sequential), got %',
                max_num + 1, NEW.linked_discount_num;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.linked_discount_num IS DISTINCT FROM OLD.linked_discount_num THEN
            SELECT COUNT(*) INTO total_count
            FROM gym_discounts_unfiltered
            WHERE gym_id = NEW.gym_id
              AND membership_plan_id = NEW.membership_plan_id
              AND discount_type = 'linked'
              AND discount_id <> NEW.discount_id;

            IF NEW.linked_discount_num < 1 OR NEW.linked_discount_num > total_count + 1 THEN
                RAISE EXCEPTION 'linked_discount_num out of range [1..%]', total_count + 1;
            END IF;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts_unfiltered
        WHERE gym_id = OLD.gym_id
          AND membership_plan_id = OLD.membership_plan_id
          AND discount_type = 'linked';

        IF OLD.linked_discount_num <> max_num THEN
            RAISE EXCEPTION 'Can only delete the highest linked_discount_num (%). Got %',
                max_num, OLD.linked_discount_num;
        END IF;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION check_linked_discount_type()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.linked_discount_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM gym_discounts_unfiltered
            WHERE discount_id = NEW.linked_discount_id
              AND discount_type = 'linked'
        ) THEN
            RAISE EXCEPTION 'linked_discount_id % must reference a discount with type linked', NEW.linked_discount_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_linked_account_hierarchy()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE account_linked_to_id = NEW.crm_user_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.crm_user_id;
        END IF;

        IF EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE crm_user_id = NEW.account_linked_to_id
              AND account_linked_to_id IS NOT NULL
        ) THEN
            RAISE EXCEPTION 'Cannot link to account % — it is already linked to another account',
                NEW.account_linked_to_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Phase 7: Update immutability triggers (allow NULL -> value for stripe IDs)

CREATE OR REPLACE FUNCTION prevent_stripe_customer_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

-- Phase 8: Update membership validation triggers (must query _unfiltered tables)

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
