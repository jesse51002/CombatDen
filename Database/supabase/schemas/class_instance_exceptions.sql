-- One-off override for a single occurrence of a class on a specific date.
-- Use class_range_exceptions for continuous-period changes.
CREATE TABLE class_instance_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_instance_exception_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_instance_exception_gym REFERENCES gyms(gym_id),
    original_date DATE NOT NULL,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    new_class_time TIME,
    new_duration_minutes INTEGER CHECK (new_duration_minutes IS NULL OR new_duration_minutes > 0),
    new_max_capacity INTEGER CHECK (new_max_capacity IS NULL OR new_max_capacity > 0),
    new_instructor_id UUID,
    -- Reschedule target: when set, this occurrence is moved off original_date to
    -- new_date (the expander suppresses original_date and emits at new_date). NULL =
    -- not rescheduled. new_date may be any date -- past, today, or future: the
    -- original_date is only the anchor the move is measured from, not a lower bound.
    new_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exception_id),
    UNIQUE (class_id, original_date),
    CONSTRAINT fk_instance_exception_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_instance_exception_instructor
        FOREIGN KEY (new_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);
