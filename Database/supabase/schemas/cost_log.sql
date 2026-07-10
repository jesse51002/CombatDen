-- Generic append-only spend ledger across every cost-bearing pipeline stage of
-- any cost-generating source. `source` names the producing system (only
-- 'video' today — the VideoService worker; extensible), and (source, run_id)
-- matches a cost row back to its source table's run (video_run.run_id for video
-- spend). `cost_usd` is the row's total; `breakdown` is a USD component map,
-- e.g. {"apify_usd": 0.18} or {"llm_usd": 0.0123}. `model` records the model
-- that produced the spend when one applies. `gym_id` attributes per-gym spend
-- to REAL gyms (NULL for spend not attributable to one gym), so per-run/per-gym
-- cost is queryable directly — the founder's per-run price visibility.
--
-- Stages: 'search' (Apify scrape), 'transcript' (legacy separate fetch), 'tag'
-- (legacy classify-only pass), 'enrich' (the worker's ONE multimodal
-- classify+summarize call per video), 'embed' (summary/probe embeddings),
-- 'scan' (keep/drop verdicts).
--
-- Service-role-written only (see access_rules/cost_log.sql).

CREATE TYPE cost_stage AS ENUM (
    'search', 'transcript', 'tag', 'enrich', 'embed', 'scan'
);
CREATE TYPE cost_source AS ENUM ('video');

CREATE TABLE cost_log (
    entry_id UUID NOT NULL DEFAULT uuid_generate_v4()
        CONSTRAINT pk_cost_log PRIMARY KEY,
    source cost_source NOT NULL,
    -- The source table's run this spend belongs to (per-run cost = SUM per
    -- run_id, scoped by source); NULL for spend outside a run.
    run_id TEXT,
    gym_id UUID
        CONSTRAINT fk_cost_log_gym REFERENCES gyms(gym_id) ON DELETE SET NULL,
    stage cost_stage NOT NULL,
    model TEXT,
    cost_usd DOUBLE PRECISION NOT NULL DEFAULT 0,
    breakdown JSONB NOT NULL DEFAULT '{}',
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cost_log_gym ON cost_log (gym_id);
CREATE INDEX idx_cost_log_run ON cost_log (run_id);
CREATE INDEX idx_cost_log_source ON cost_log (source);
