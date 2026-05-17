-- Append-only log of class instances that actually occurred. Pairs with
-- member_attendance (each attendance row references the same class_id +
-- occurred_at). Decoupled from gym_classes/exceptions so historical records
-- survive class config changes.
CREATE TABLE class_history (
    class_history_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_class_history_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_class_history_gym REFERENCES gyms(gym_id),
    instructor_id UUID,
    occurred_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (class_history_id),
    UNIQUE (class_history_id, gym_id),
    CONSTRAINT fk_class_history_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_history_instructor
        FOREIGN KEY (instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);

CREATE INDEX idx_class_history_class_time
    ON class_history (class_id, occurred_at DESC);
