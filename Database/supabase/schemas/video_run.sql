-- A versioned run that built a gym's video feed: one row per scan / preset
-- import. Each gym_video_feed row from that run carries its video_run_id, so the
-- serve path can select only the gym's LATEST run (old runs are retained as
-- history). Owner-added "Your videos" rows are run-independent (video_run_id
-- NULL) and always serve, surviving every re-run.
CREATE TABLE video_run (
    run_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_video_run PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_video_run_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- "Latest run for a gym": ORDER BY created_at DESC LIMIT 1 per gym.
CREATE INDEX idx_video_run_gym_created ON video_run (gym_id, created_at DESC);
