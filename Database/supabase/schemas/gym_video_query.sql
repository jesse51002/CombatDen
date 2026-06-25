-- A real customer gym's YouTube search queries — the prod counterpart of the
-- template `video_gym_query`. These seed the (separate) batch job's scrape of the
-- shared pool for this gym. Order is irrelevant, so a surrogate UUID is the PK.
-- The preset import copies these from the chosen template.

CREATE TABLE gym_video_query (
    query_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_query_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    query TEXT NOT NULL CONSTRAINT gym_video_query_nonempty CHECK (query <> ''),
    CONSTRAINT pk_gym_video_query PRIMARY KEY (query_id)
);

CREATE INDEX idx_gym_video_query_gym ON gym_video_query (gym_id);
