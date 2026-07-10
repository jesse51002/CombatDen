-- A gym's branded class cards (ClassImage). Surrogate UUID PK; order isn't
-- significant (the API serves them ORDER BY name). Absent when the gym has no
-- classes authored (template_gym.has_classes = FALSE, zero rows).

CREATE TABLE template_gym_class (
    class_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id TEXT NOT NULL
        CONSTRAINT fk_template_gym_class_gym REFERENCES template_gym(gym_id) ON DELETE CASCADE,
    name TEXT NOT NULL CONSTRAINT template_gym_class_name_nonempty CHECK (name <> ''),
    image_url TEXT NOT NULL CONSTRAINT template_gym_class_image_url_nonempty CHECK (image_url <> ''),
    description TEXT NOT NULL CONSTRAINT template_gym_class_description_nonempty CHECK (description <> ''),
    instructor_name TEXT NOT NULL
        CONSTRAINT template_gym_class_instructor_name_nonempty CHECK (instructor_name <> ''),
    instructor_bio TEXT NOT NULL
        CONSTRAINT template_gym_class_instructor_bio_nonempty CHECK (instructor_bio <> ''),
    instructor_image_url TEXT NOT NULL
        CONSTRAINT template_gym_class_instructor_image_url_nonempty CHECK (instructor_image_url <> ''),
    CONSTRAINT pk_template_gym_class PRIMARY KEY (class_id)
);

CREATE INDEX idx_template_gym_class_gym ON template_gym_class (gym_id);
