-- Per-gym rank ladder. Cloned from a rank_preset at onboarding then
-- editable by gym staff. Members reference these rows via
-- members.current_rank_id.
CREATE TABLE gym_ranks (
    rank_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_rank_gym REFERENCES gyms(gym_id),
    main_rank_num_order INTEGER NOT NULL CHECK (main_rank_num_order >= 0),
    sub_rank_num_order INTEGER NOT NULL CHECK (sub_rank_num_order >= 0),
    main_name VARCHAR NOT NULL CHECK (main_name <> ''),
    sub_name VARCHAR NOT NULL CHECK (sub_name <> ''),
    classes_till_rankup INTEGER NOT NULL CHECK (classes_till_rankup >= 0),
    image_url VARCHAR,
    color VARCHAR CHECK (color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (rank_id),
    UNIQUE (rank_id, gym_id),
    UNIQUE (gym_id, main_rank_num_order, sub_rank_num_order)
);
