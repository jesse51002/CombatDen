-- Continuous-period override: cancel the class across [start_date, end_date]
-- and/or substitute the instructor across that range. Time/duration changes
-- are not in scope for range exceptions; for those use class_instance_exceptions.
CREATE TABLE class_range_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_range_exception_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_range_exception_gym REFERENCES gyms(gym_id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    new_instructor_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exception_id),
    CHECK (end_date >= start_date),
    CHECK (is_cancelled OR new_instructor_id IS NOT NULL),
    CONSTRAINT fk_range_exception_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_range_exception_instructor
        FOREIGN KEY (new_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);
