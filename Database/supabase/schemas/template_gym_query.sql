-- The YouTube search queries that populate a gym's slice of the pool. Authored
-- per gym; order is irrelevant (the scraper just needs the set), so a surrogate
-- UUID is the PK and there is no position column.

CREATE TABLE template_gym_query (
    query_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id TEXT NOT NULL
        CONSTRAINT fk_template_gym_query_gym REFERENCES template_gym(gym_id) ON DELETE CASCADE,
    query TEXT NOT NULL CONSTRAINT template_gym_query_nonempty CHECK (query <> ''),
    CONSTRAINT pk_template_gym_query PRIMARY KEY (query_id)
);

CREATE INDEX idx_template_gym_query_gym ON template_gym_query (gym_id);
