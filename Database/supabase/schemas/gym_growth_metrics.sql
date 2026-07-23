-- Generic per-gym analytics metric store — the Growth page's cache.
-- The backend's growth domain recomputes every metric at launch and hourly,
-- UPSERTing one row per (gym_id, key). Display metadata (name, categories,
-- order) is deliberately NOT stored: it lives in the backend registry and is
-- attached at serve time, so a rename or reorder needs no recompute.
--
-- `data` is a type-shaped jsonb payload validated on READ against the
-- registry's Pydantic model for `key`. A row whose key is unknown or whose
-- payload no longer matches is skipped at serve time and self-heals at the next
-- compute — the fault-tolerance contract for rolling deploys / multiple
-- backend containers. `type` is a denormalized write-time copy of the
-- registry's type, kept for debugging only; the registry always wins on read.
CREATE TABLE gym_growth_metrics (
    metric_id UUID NOT NULL DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL CONSTRAINT fk_growth_metrics_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    type TEXT NOT NULL,
    data JSONB NOT NULL CONSTRAINT growth_metrics_data_is_object CHECK (jsonb_typeof(data) = 'object'),
    computed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (metric_id),
    CONSTRAINT uq_growth_metrics_gym_key UNIQUE (gym_id, key)
);

-- The serve path reads every metric for one gym in a single indexed scan.
CREATE INDEX idx_gym_growth_metrics_gym_id ON gym_growth_metrics (gym_id);
