-- A real customer gym's served video feed: the set of shared-pool videos approved
-- for this gym. Presence == approved/served (a video absent from a gym's rows is
-- simply not in its feed) — the lean prod counterpart of the template
-- `video_gym_feed`, which keeps an explicit good/rejected audit. Order isn't
-- stored; the API serves the feed ORDER BY video.relevance_index. The preset
-- import rewrites a gym's rows; the (separate) batch job will own them thereafter.

CREATE TABLE gym_video_feed (
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_feed_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_gym_video_feed_video REFERENCES video(video_id) ON DELETE CASCADE,
    CONSTRAINT pk_gym_video_feed PRIMARY KEY (gym_id, video_id)
);

-- Serve a gym's feed (the join to `video` supplies relevance ordering + cards).
CREATE INDEX idx_gym_video_feed_gym ON gym_video_feed (gym_id);
