-- Append-only spend ledger across every cost-bearing VideoService run
-- (search/transcript/tag/scan). Mirrors VideoService/cost_log.yaml. `breakdown`
-- is a USD component map, e.g. {"apify_usd": 0.18} or {"llm_usd": 0.0123}.
-- `gym_id` attributes per-gym spend (set on scan entries; NULL for pool-wide
-- search/tag runs), so per-gym scan cost is queryable without a separate table.

CREATE TYPE video_execution_type AS ENUM ('search', 'transcript', 'tag', 'scan');

CREATE TABLE video_cost_log (
    entry_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    execution_type video_execution_type NOT NULL,
    gym_id TEXT
        CONSTRAINT fk_video_cost_log_gym REFERENCES video_gym(gym_id) ON DELETE SET NULL,
    at TIMESTAMPTZ NOT NULL,
    breakdown JSONB NOT NULL DEFAULT '{}',
    note TEXT,
    CONSTRAINT pk_video_cost_log PRIMARY KEY (entry_id)
);

CREATE INDEX idx_video_cost_log_gym ON video_cost_log (gym_id);
