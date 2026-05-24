CREATE TYPE recurring_unit AS ENUM ('daily', 'weekly', 'monthly');

CREATE TABLE gym_classes (
    class_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_gym REFERENCES gyms(gym_id),
    class_name VARCHAR NOT NULL CHECK (class_name <> ''),
    class_description VARCHAR,
    max_capacity INTEGER CHECK (max_capacity > 0),
    image_url VARCHAR,
    points_worth INTEGER NOT NULL DEFAULT 50 CHECK (points_worth > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,

    -- Embedded recurring schedule (one root schedule per class). Overlapping
    -- schedules across different classes are allowed.
    class_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    recurring_unit recurring_unit NOT NULL,
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
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (class_id),
    UNIQUE (class_id, gym_id),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CHECK (recurring_unit != 'weekly' OR sun OR mon OR tue OR wed OR thu OR fri OR sat),

    CONSTRAINT fk_class_sun_instructor
        FOREIGN KEY (sun_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_mon_instructor
        FOREIGN KEY (mon_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_tue_instructor
        FOREIGN KEY (tue_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_wed_instructor
        FOREIGN KEY (wed_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_thu_instructor
        FOREIGN KEY (thu_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_fri_instructor
        FOREIGN KEY (fri_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_sat_instructor
        FOREIGN KEY (sat_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);
