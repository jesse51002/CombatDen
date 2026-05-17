-- Global rank-ladder presets keyed by gym_type. Static reference data.
-- Gyms clone a preset into gym_ranks at onboarding instead of typing
-- every belt + stripe themselves.
CREATE TYPE gym_type AS ENUM ('bjj', 'mma', 'generic');

CREATE TABLE rank_presets (
    preset_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_type gym_type NOT NULL,
    main_rank_num_order INTEGER NOT NULL CHECK (main_rank_num_order >= 0),
    sub_rank_num_order INTEGER NOT NULL CHECK (sub_rank_num_order >= 0),
    main_name VARCHAR NOT NULL CHECK (main_name <> ''),
    sub_name VARCHAR NOT NULL CHECK (sub_name <> ''),
    classes_till_rankup INTEGER NOT NULL CHECK (classes_till_rankup >= 0),
    image_url VARCHAR,
    color VARCHAR CHECK (color IS NULL OR color ~ '^#[0-9A-Fa-f]{6}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (preset_id),
    UNIQUE (gym_type, main_rank_num_order, sub_rank_num_order)
);
