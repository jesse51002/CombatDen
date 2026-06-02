-- The YouTube search queries that populate a gym's slice of the pool. Authored
-- per gym; order is irrelevant (the scraper just needs the set), so a surrogate
-- UUID is the PK and there is no position column.

CREATE TABLE video_gym_query (
    query_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id TEXT NOT NULL
        CONSTRAINT fk_video_gym_query_gym REFERENCES video_gym(gym_id) ON DELETE CASCADE,
    query TEXT NOT NULL CONSTRAINT video_gym_query_nonempty CHECK (query <> ''),
    CONSTRAINT pk_video_gym_query PRIMARY KEY (query_id)
);

CREATE INDEX idx_video_gym_query_gym ON video_gym_query (gym_id);
