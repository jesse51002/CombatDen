-- The video worker's job queue: one pending row per gym awaiting a
-- scrape/enrich/scan run. Postgres IS the queue — the FastApiBackend enqueues
-- (spec commit seam + the CRM's manual run endpoint) and the VideoService
-- worker process pops (DELETE ... RETURNING, oldest requested_at first),
-- one run at a time under the global video-worker resource lock.
--
-- gym_id is the PK: a gym is queued at most once. The enqueue upsert keeps
-- the OLDEST requested_at on conflict (anti-self-starvation — a gym editing
-- its spec repeatedly must not keep pushing itself behind newer requests).
CREATE TYPE video_worker_reason AS ENUM ('spec_update', 'manual');

CREATE TABLE video_worker_queue (
    gym_id UUID NOT NULL
        CONSTRAINT pk_video_worker_queue PRIMARY KEY
        CONSTRAINT fk_video_worker_queue_gym
            REFERENCES gyms(gym_id) ON DELETE CASCADE,
    reason video_worker_reason NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pop order: oldest request first.
CREATE INDEX idx_video_worker_queue_requested
    ON video_worker_queue (requested_at);
