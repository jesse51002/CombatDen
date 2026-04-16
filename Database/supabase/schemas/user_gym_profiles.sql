CREATE TABLE user_gym_profiles_unfiltered (
    crm_user_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_profile_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_profile_gym REFERENCES gyms_unfiltered(gym_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_class TIMESTAMPTZ,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    photo_url VARCHAR,
    phone VARCHAR,
    email VARCHAR,
    address VARCHAR,
    emergency_contact_name VARCHAR,
    emergency_contact_phone VARCHAR,
    emergency_contact_email VARCHAR,
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    freeze_start_date DATE,
    freeze_end_date DATE,
    CONSTRAINT freeze_dates_must_be_paired
        CHECK (
            (freeze_start_date IS NULL AND freeze_end_date IS NULL)
            OR (freeze_start_date IS NOT NULL AND freeze_end_date IS NOT NULL)
        ),
    account_linked_to_id UUID,
    linked_discount_id UUID CONSTRAINT fk_profile_linked_discount REFERENCES gym_discounts_unfiltered(discount_id),
    stripe_customer_id VARCHAR,
    stripe_sub_id_month VARCHAR,
    stripe_payment_method_id VARCHAR,
    payment_type VARCHAR,
    card_brand VARCHAR,
    card_last_four VARCHAR(4),
    card_exp_month INTEGER,
    card_exp_year INTEGER,
    total_monthly_recurring_price INTEGER NOT NULL DEFAULT 0
        CHECK (total_monthly_recurring_price >= 0),
    PRIMARY KEY (crm_user_id),
    UNIQUE (crm_user_id, gym_id),
    CONSTRAINT linked_account_no_stripe
        CHECK (
            account_linked_to_id IS NULL
            OR (
                stripe_sub_id_month IS NULL
                AND freeze_start_date IS NULL
                AND freeze_end_date IS NULL
                AND payment_type IS NULL
                AND card_brand IS NULL
                AND card_last_four IS NULL
                AND card_exp_month IS NULL
                AND card_exp_year IS NULL
            )
        ),
    CONSTRAINT fk_profile_linked_account_same_gym
        FOREIGN KEY (account_linked_to_id, gym_id)
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id),
    CONSTRAINT fk_profile_linked_discount_gym
        FOREIGN KEY (linked_discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

-- Partial unique index: a user can only have one profile per gym
CREATE UNIQUE INDEX unique_user_gym
    ON user_gym_profiles_unfiltered (user_id, gym_id)
    WHERE user_id IS NOT NULL;

-- Unique index: each Stripe customer maps to exactly one profile
CREATE UNIQUE INDEX idx_profiles_stripe_customer
    ON user_gym_profiles_unfiltered (stripe_customer_id);

-- Trigger: once user_id is set, it cannot be changed to a different value
CREATE OR REPLACE FUNCTION prevent_user_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_user_id_overwrite
    BEFORE UPDATE OF user_id ON user_gym_profiles_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_overwrite();

-- Trigger: stripe_customer_id is immutable
CREATE OR REPLACE FUNCTION prevent_stripe_customer_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_customer_id IS NOT NULL AND NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN
        RAISE EXCEPTION 'stripe_customer_id cannot be changed after creation (crm_user_id: %)', OLD.crm_user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_stripe_customer_id_overwrite
    BEFORE UPDATE OF stripe_customer_id ON user_gym_profiles_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_stripe_customer_id_overwrite();

-- Trigger: an account cannot be both a parent and a child in linked accounts
CREATE OR REPLACE FUNCTION enforce_linked_account_hierarchy()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_linked_to_id IS NOT NULL THEN
        -- This profile is becoming a child — ensure it is not already a parent
        IF EXISTS (
            SELECT 1 FROM user_gym_profiles_unfiltered
            WHERE account_linked_to_id = NEW.crm_user_id
        ) THEN
            RAISE EXCEPTION 'Cannot link account % to a parent — it already has linked child accounts',
                NEW.crm_user_id;
        END IF;

        -- Ensure the target parent is not itself a child
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

CREATE TRIGGER trg_enforce_linked_account_hierarchy
    BEFORE INSERT OR UPDATE OF account_linked_to_id ON user_gym_profiles_unfiltered
    FOR EACH ROW EXECUTE FUNCTION enforce_linked_account_hierarchy();

-- Trigger: linked_discount_id must reference a discount with discount_type = 'linked'
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

CREATE TRIGGER trg_check_linked_discount_type
    BEFORE INSERT OR UPDATE OF linked_discount_id ON user_gym_profiles_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_linked_discount_type();

-- View: only exposes profiles with a completed Stripe customer sync
CREATE VIEW user_gym_profiles
WITH (security_invoker = true)
AS
SELECT * FROM user_gym_profiles_unfiltered
WHERE stripe_customer_id IS NOT NULL;

ALTER VIEW user_gym_profiles SET (security_invoker = true);
