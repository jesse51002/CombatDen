CREATE TABLE gym_discounts (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    discount_type VARCHAR NOT NULL CHECK (discount_type IN ('preset', 'custom', 'linked')),
    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off INTEGER CHECK (dollar_off > 0),
    membership_plan_id UUID CONSTRAINT fk_discount_plan REFERENCES membership_plans(plan_id),
    linked_discount_num INTEGER CHECK (linked_discount_num > 0),
    duration VARCHAR NOT NULL CHECK (duration IN ('once', 'repeating', 'forever')),
    duration_in_months INTEGER CHECK (duration_in_months > 0),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    stripe_coupon_id VARCHAR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (discount_id),
    UNIQUE (discount_id, gym_id),
    CHECK (num_nonnulls(percentage_off, dollar_off) = 1),
    CONSTRAINT chk_linked_discount_fields CHECK (
        (discount_type = 'linked' AND membership_plan_id IS NOT NULL AND linked_discount_num IS NOT NULL AND dollar_off IS NOT NULL)
        OR (discount_type <> 'linked' AND membership_plan_id IS NULL AND linked_discount_num IS NULL)
    ),
    CONSTRAINT chk_duration_in_months CHECK (
        (duration = 'repeating' AND duration_in_months IS NOT NULL)
        OR (duration <> 'repeating' AND duration_in_months IS NULL)
    ),
    UNIQUE (gym_id, membership_plan_id, linked_discount_num),
    CONSTRAINT fk_discount_plan_gym
        FOREIGN KEY (membership_plan_id, gym_id)
        REFERENCES membership_plans (plan_id, gym_id)
);

-- Enable Row Level Security
ALTER TABLE gym_discounts ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their discounts
CREATE POLICY "Gym staff can view discounts"
    ON gym_discounts
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_discounts.gym_id));

-- Column-level permissions: no INSERT/UPDATE for authenticated (stripe rule)
REVOKE INSERT, UPDATE ON TABLE gym_discounts FROM authenticated;

-- Trigger: enforce sequential linked_discount_num per (gym_id, membership_plan_id)
-- INSERT: must be max + 1
-- UPDATE: must stay within [1..count]
-- DELETE: only the highest num can be deleted (reject gaps)
CREATE OR REPLACE FUNCTION enforce_linked_discount_sequence()
RETURNS TRIGGER AS $$
DECLARE
    max_num INTEGER;
    total_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT COALESCE(MAX(linked_discount_num), 0) INTO max_num
        FROM gym_discounts
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
            FROM gym_discounts
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
        FROM gym_discounts
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

-- Split into two triggers because WHEN clause can't reference both NEW and OLD
CREATE TRIGGER trg_enforce_linked_discount_sequence_insert_update
    BEFORE INSERT OR UPDATE OF linked_discount_num ON gym_discounts
    FOR EACH ROW
    WHEN (NEW.discount_type = 'linked')
    EXECUTE FUNCTION enforce_linked_discount_sequence();

CREATE TRIGGER trg_enforce_linked_discount_sequence_delete
    BEFORE DELETE ON gym_discounts
    FOR EACH ROW
    WHEN (OLD.discount_type = 'linked')
    EXECUTE FUNCTION enforce_linked_discount_sequence();
