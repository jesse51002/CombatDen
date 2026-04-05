CREATE TABLE gym_class_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    schedule_id UUID NOT NULL CONSTRAINT fk_exception_schedule_id REFERENCES gym_class_schedules(schedule_id),
    gym_id UUID NOT NULL CONSTRAINT fk_exception_gym REFERENCES gyms(gym_id),
    original_date DATE NOT NULL,
    is_cancelled BOOLEAN,
    new_class_time TIME,
    new_duration_minutes INTEGER CHECK (new_duration_minutes > 0),
    new_max_capacity INTEGER CHECK (new_max_capacity > 0),
    new_instructor_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exception_id),
    CONSTRAINT fk_exception_schedule
        FOREIGN KEY (schedule_id, gym_id)
        REFERENCES gym_class_schedules (schedule_id, gym_id),
    CONSTRAINT fk_exception_instructor
        FOREIGN KEY (new_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    UNIQUE (schedule_id, original_date)
);

-- Enable Row Level Security
ALTER TABLE gym_class_exceptions ENABLE ROW LEVEL SECURITY;

-- Policy: All employees can view exceptions
CREATE POLICY "Gym employees can view exceptions"
    ON gym_class_exceptions
    FOR SELECT
    USING (is_gym_employee(gym_class_exceptions.gym_id));

-- Policy: Members can view exceptions for their gym
CREATE POLICY "Members can view exceptions"
    ON gym_class_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_gym_profiles
            WHERE user_gym_profiles.gym_id = gym_class_exceptions.gym_id
            AND user_gym_profiles.user_id = auth.uid()
        )
    );

-- Policy: Gym staff can insert exceptions
CREATE POLICY "Gym staff can insert exceptions"
    ON gym_class_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_class_exceptions.gym_id));

-- Policy: Gym staff can update exceptions
CREATE POLICY "Gym staff can update exceptions"
    ON gym_class_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_class_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_class_exceptions.gym_id));

-- Column-level permissions: Revoke UPDATE on immutable columns
REVOKE UPDATE (exception_id, schedule_id, gym_id, original_date, created_at) ON TABLE gym_class_exceptions FROM authenticated;
