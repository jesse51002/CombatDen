CREATE TABLE gym_class_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    schedule_id UUID NOT NULL CONSTRAINT fk_exception_schedule_id REFERENCES gym_class_schedules(schedule_id),
    gym_id UUID NOT NULL CONSTRAINT fk_exception_gym REFERENCES gyms_unfiltered(gym_id),
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
