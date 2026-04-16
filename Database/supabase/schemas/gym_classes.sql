CREATE TABLE gym_classes (
    class_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_gym REFERENCES gyms_unfiltered(gym_id),
    class_name VARCHAR NOT NULL CHECK (class_name <> ''),
    class_description VARCHAR,
    allowed_plan_ids JSONB,
    max_capacity INTEGER CHECK (max_capacity > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (class_id),
    UNIQUE (class_id, gym_id)
);

-- Trigger: validates that every UUID in allowed_plan_ids exists in membership_plans for the same gym
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

CREATE TRIGGER trg_check_class_plan_ids_gym_match
    BEFORE INSERT OR UPDATE OF allowed_plan_ids ON gym_classes
    FOR EACH ROW EXECUTE FUNCTION check_class_plan_ids_gym_match();
