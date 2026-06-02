-- The per-gym curated feed: the scan's keep/drop verdict over the shared pool.
-- A video is 'good' (served) or 'rejected' (audit only) for a gym, never both
-- (PK is (gym_id, video_id)). Order isn't stored — the API serves the feed
-- ORDER BY video.relevance_index. The scan owns this table; it rewrites a gym's
-- rows on every run.

CREATE TYPE video_gym_feed_status AS ENUM ('good', 'rejected');

CREATE TABLE video_gym_feed (
    gym_id TEXT NOT NULL
        CONSTRAINT fk_video_gym_feed_gym REFERENCES video_gym(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_video_gym_feed_video REFERENCES video(video_id) ON DELETE CASCADE,
    status video_gym_feed_status NOT NULL,
    CONSTRAINT pk_video_gym_feed PRIMARY KEY (gym_id, video_id)
);

-- Filter a gym's feed by status; relevance ordering comes from the joined video.
CREATE INDEX idx_video_gym_feed_serve ON video_gym_feed (gym_id, status);
