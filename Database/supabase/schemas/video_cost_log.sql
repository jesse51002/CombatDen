-- Append-only spend ledger across every cost-bearing video pipeline stage.
-- `breakdown` is a USD component map, e.g. {"apify_usd": 0.18} or
-- {"llm_usd": 0.0123}. `gym_id` attributes per-gym spend to REAL gyms (the
-- worker stamps it on every stage of a gym's run; NULL for spend not
-- attributable to one gym), so per-run/per-gym cost is queryable directly —
-- the founder's per-run price visibility.
--
-- Execution types: 'search' (Apify scrape), 'transcript' (legacy separate
-- fetch), 'tag' (legacy classify-only pass), 'enrich' (the worker's ONE
-- multimodal classify+summarize call per video), 'embed' (summary/probe
-- embeddings), 'scan' (keep/drop verdicts).
--
-- Historical note: this ledger predates real-gym runs (it mirrored
-- VideoService/cost_log.yaml, attributed to TEXT video_gym template slugs).
-- The retype to UUID→gyms keeps legacy rows' spend but moves their template
-- attribution into `note` ('template:<slug>').

CREATE TYPE video_execution_type AS ENUM (
    'search', 'transcript', 'tag', 'enrich', 'embed', 'scan'
);

CREATE TABLE video_cost_log (
    entry_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    execution_type video_execution_type NOT NULL,
    gym_id UUID
        CONSTRAINT fk_video_cost_log_gym REFERENCES gyms(gym_id) ON DELETE SET NULL,
    -- The worker run this spend belongs to (per-run cost = SUM per run_id);
    -- NULL for legacy rows and spend outside a run.
    video_run_id UUID
        CONSTRAINT fk_video_cost_log_run REFERENCES video_run(run_id) ON DELETE SET NULL,
    at TIMESTAMPTZ NOT NULL,
    breakdown JSONB NOT NULL DEFAULT '{}',
    note TEXT,
    CONSTRAINT pk_video_cost_log PRIMARY KEY (entry_id)
);

CREATE INDEX idx_video_cost_log_gym ON video_cost_log (gym_id);
CREATE INDEX idx_video_cost_log_run ON video_cost_log (video_run_id);
