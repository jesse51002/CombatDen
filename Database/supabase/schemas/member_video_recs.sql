-- Recommendation history: one row per (member, video) that has ever been
-- SERVED as a recommendation. Freshness is the point — the rec ranking hard-
-- partitions unrecommended videos first, then previously-recommended by
-- oldest last_recommended_at — so the same video is never repeatedly pushed
-- while unseen candidates exist. "Already recommended" is global per member
-- (not per-bucket): a video served under any bucket counts as seen.
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
    -- The bucket it was served under (analytics / bucket-mix tuning).
    bucket mood_bucket NOT NULL,
    -- The composite score at (last) serve time: RAG cosine dominant, blended
    -- with gym relevance + popularity per the backend's weight settings.
    score DOUBLE PRECISION NOT NULL,
    first_recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    times_recommended INTEGER NOT NULL DEFAULT 1
        CONSTRAINT member_video_recs_times_positive
            CHECK (times_recommended > 0),
    -- One row per member+video; a re-serve bumps last_recommended_at /
    -- times_recommended instead of inserting (ON CONFLICT upsert anchor).
    CONSTRAINT uq_member_video_recs_member_video UNIQUE (member_id, video_id),
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- The rec query's anti-join ("not yet recommended") and history reads are
-- member-scoped.
CREATE INDEX idx_member_video_recs_member ON member_video_recs (member_id);
