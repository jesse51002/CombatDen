-- Global rank-ladder presets keyed by rank_preset_kind. Static reference
-- data. Gyms clone a preset into gym_ranks at onboarding. One row per MAIN
-- rank, matching the new gym_ranks shape.
CREATE TYPE rank_preset_kind AS ENUM ('bjj_belts', 'bjj_belts_stripes', 'flat');

CREATE TABLE rank_presets (
    preset_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    preset_kind rank_preset_kind NOT NULL,
    main_rank_num_order INTEGER NOT NULL CHECK (main_rank_num_order >= 0),
    name VARCHAR NOT NULL CHECK (name <> ''),
    image_url VARCHAR,
    classes_to_next_major INTEGER NOT NULL CHECK (classes_to_next_major >= 0),
    sub_rank_count INTEGER NOT NULL DEFAULT 0 CHECK (sub_rank_count >= 0),
    -- The gym sub_rank_type this preset implies; NULL when it has no
    -- sub-ranks. from_preset copies MAX(implied_sub_rank_type) onto the gym.
    implied_sub_rank_type sub_rank_type,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (preset_id),
    UNIQUE (preset_kind, main_rank_num_order)
);
