CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE gym_class_schedules (
    schedule_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_schedule_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_schedule_gym REFERENCES gyms(gym_id),
    class_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    recurring_unit VARCHAR NOT NULL CHECK (recurring_unit IN ('daily', 'weekly', 'monthly')),
    recurring_interval INTEGER NOT NULL DEFAULT 1 CHECK (recurring_interval > 0),
    sun BOOLEAN NOT NULL DEFAULT FALSE,
    mon BOOLEAN NOT NULL DEFAULT FALSE,
    tue BOOLEAN NOT NULL DEFAULT FALSE,
    wed BOOLEAN NOT NULL DEFAULT FALSE,
    thu BOOLEAN NOT NULL DEFAULT FALSE,
    fri BOOLEAN NOT NULL DEFAULT FALSE,
    sat BOOLEAN NOT NULL DEFAULT FALSE,
    sun_instructor_id UUID,
    mon_instructor_id UUID,
    tue_instructor_id UUID,
    wed_instructor_id UUID,
    thu_instructor_id UUID,
    fri_instructor_id UUID,
    sat_instructor_id UUID,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (schedule_id),
    UNIQUE (schedule_id, gym_id),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CHECK (recurring_unit != 'weekly' OR sun OR mon OR tue OR wed OR thu OR fri OR sat),
    CONSTRAINT fk_schedule_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_sched_sun_instructor
        FOREIGN KEY (sun_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_mon_instructor
        FOREIGN KEY (mon_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_tue_instructor
        FOREIGN KEY (tue_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_wed_instructor
        FOREIGN KEY (wed_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_thu_instructor
        FOREIGN KEY (thu_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_fri_instructor
        FOREIGN KEY (fri_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_sched_sat_instructor
        FOREIGN KEY (sat_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    -- No overlapping date ranges for the same class
    EXCLUDE USING gist (
        class_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
);

-- Enable Row Level Security
ALTER TABLE gym_class_schedules ENABLE ROW LEVEL SECURITY;

-- Policy: All employees can view schedules
CREATE POLICY "Gym employees can view schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (is_gym_employee(gym_class_schedules.gym_id));

-- Policy: Members can view schedules for active classes in their gym
CREATE POLICY "Members can view schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gym_classes
            WHERE gym_classes.class_id = gym_class_schedules.class_id
            AND gym_classes.is_active = true
        )
        AND EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_class_schedules.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert schedules
CREATE POLICY "Gym staff can insert schedules"
    ON gym_class_schedules
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_class_schedules.gym_id));

-- Policy: Gym staff can update schedules
CREATE POLICY "Gym staff can update schedules"
    ON gym_class_schedules
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_class_schedules.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_class_schedules.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (schedule_id, class_id, gym_id, start_date, created_at) ON TABLE gym_class_schedules FROM authenticated;

-- Trigger: ensures no gaps between schedule segments for the same class
CREATE OR REPLACE FUNCTION check_no_schedule_gaps()
RETURNS TRIGGER AS $$
DECLARE
    target_class_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_class_id := OLD.class_id;
    ELSE
        target_class_id := NEW.class_id;
    END IF;

    -- Skip check if no segments remain for this class
    IF NOT EXISTS (
        SELECT 1 FROM gym_class_schedules WHERE class_id = target_class_id
    ) THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Check for gaps: any segment that ends without another starting the next day
    IF EXISTS (
        SELECT 1
        FROM gym_class_schedules a
        LEFT JOIN gym_class_schedules b
            ON b.class_id = a.class_id
            AND b.start_date = a.end_date + 1
        WHERE a.class_id = target_class_id
            AND a.end_date IS NOT NULL
            AND b.schedule_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Gap detected in schedule for class %', target_class_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_no_schedule_gaps
    AFTER INSERT OR UPDATE OR DELETE
    ON gym_class_schedules
    FOR EACH ROW EXECUTE FUNCTION check_no_schedule_gaps();
