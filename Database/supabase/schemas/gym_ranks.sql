-- Per-gym rank ladder: ONE row per MAIN rank. Cloned from a rank_preset at
-- onboarding then editable by gym staff. A main rank is a leaf when
-- sub_rank_count = 0; otherwise it has sub_rank_count leaf sub-positions
-- (0-based current_sub_index on members). Sub-rank LABELS are derived from
-- the gym's sub_rank_type + the index, never stored. Members reference these
-- rows via members.current_rank_id (+ members.current_sub_index).
CREATE TABLE gym_ranks (
    rank_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_rank_gym REFERENCES gyms(gym_id),
    main_rank_num_order INTEGER NOT NULL CHECK (main_rank_num_order >= 0),
    name VARCHAR NOT NULL CHECK (name <> ''),
    image_url VARCHAR,
    -- Headline threshold to reach the NEXT main rank; per-sub-step thresholds
    -- are DERIVED (even split across the sub-positions), not stored.
    classes_to_next_major INTEGER NOT NULL CHECK (classes_to_next_major >= 0),
    -- 0 = this main rank is itself the leaf (current_sub_index NULL); N>=1 = N
    -- leaf sub-positions, current_sub_index in [0, N-1].
    sub_rank_count INTEGER NOT NULL DEFAULT 0 CHECK (sub_rank_count >= 0),
    -- Sparse {sub_index: url} overrides for per-sub images that diverge from
    -- image_url; PERSIST-ONLY (never pruned on count shrink / type change);
    -- effective sub image = override[idx] else image_url.
    sub_rank_image_overrides JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (rank_id),
    UNIQUE (rank_id, gym_id),
    UNIQUE (gym_id, main_rank_num_order)
);
