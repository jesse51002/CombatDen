-- A versioned run that built a gym's video feed: one row per scan / preset
-- import. Each gym_video_feed row from that run carries its video_run_id, so the
-- serve path can select only the gym's LATEST run (old runs are retained as
-- history). Owner-added "Your videos" rows are run-independent (video_run_id
-- NULL) and always serve, surviving every re-run.
--
-- `status` is the worker-run lifecycle. The serve path selects the latest
-- COMPLETED run — a 'running' run (the worker's hours-long pipeline is mid-
-- flight) must never become "latest" or the gym's feed would blank until it
-- finishes. DEFAULT 'completed' so the preset import's plain
-- INSERT (gym_id) — which writes its feed rows in the same committed
-- transaction — keeps serving unchanged; only the worker inserts
-- status='running' explicitly and finalizes to completed/failed.
CREATE TYPE video_run_status AS ENUM ('running', 'completed', 'failed');

CREATE TABLE video_run (
    run_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_video_run PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_video_run_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    status video_run_status NOT NULL DEFAULT 'completed',
    -- Set when the run reaches completed/failed; NULL while running.
    finished_at TIMESTAMPTZ,
    -- Failure detail for a 'failed' run (exception summary or 'orphaned' when
    -- the worker found it dead on lock acquisition).
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- "Latest run for a gym": ORDER BY created_at DESC LIMIT 1 per gym (the serve
-- path adds AND status = 'completed').
CREATE INDEX idx_video_run_gym_created ON video_run (gym_id, created_at DESC);
