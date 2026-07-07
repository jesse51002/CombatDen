-- Recommendation history: an APPEND-ONLY event log — one row per (member,
-- video) SERVE. Freshness is the point — the rec ranking hard-partitions
-- unrecommended videos first, then previously-recommended by oldest last serve
-- (the per-video MAX(recommended_at)) — so the same video is never repeatedly
-- pushed while unseen candidates exist. "Already recommended" is global per
-- member (not per-bucket): a video served under any bucket counts as seen.
--
-- No stored counters: a re-serve INSERTs another row rather than bumping a
-- column, so "times recommended" = COUNT(*) and "last recommended" =
-- MAX(recommended_at), both derived by aggregate when a read needs them.
--
-- Written only when a recommendation is actually SERVED (record=true); CRM
-- previews pass record=false and leave no trace here.
CREATE TABLE member_video_recs (
    rec_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_member_video_recs PRIMARY KEY,
    member_id UUID NOT NULL
        CONSTRAINT fk_member_video_recs_member
            REFERENCES members(member_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL
        CONSTRAINT fk_member_video_recs_gym
            REFERENCES gyms(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_member_video_recs_video
            REFERENCES video(video_id) ON DELETE CASCADE,
    -- The bucket it was served under at this event (analytics / bucket-mix).
    bucket mood_bucket NOT NULL,
    -- The composite score at this serve: RAG cosine dominant, blended with gym
    -- relevance + popularity per the backend's weight settings.
    score DOUBLE PRECISION NOT NULL,
    recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- The rec query's "already recommended" anti-join and the per-video last-serve
-- aggregate (MAX(recommended_at)) both filter by member and group by video.
CREATE INDEX idx_member_video_recs_member_video
    ON member_video_recs (member_id, video_id);
