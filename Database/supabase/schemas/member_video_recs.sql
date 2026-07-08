-- Recommendation history: an APPEND-ONLY event log — one row per (member,
-- video) SERVE. Freshness is the point — the rec ranking hard-partitions
-- unrecommended videos first, then previously-recommended by oldest last serve
-- (the per-video MAX(recommended_at)) — so the same video is never repeatedly
-- pushed while unseen candidates exist. "Already recommended" is global per
-- member (not per-category): a video served under any genre category counts as
-- seen.
--
-- Recs are grouped by the video's genre CATEGORY (its `video.tag` — the
-- `video_genre` enum created in schemas/video.sql). There is no separate
-- abstraction over the genre: `category` stores the video's actual genre and
-- RAG ranks WITHIN a category. Consumed by this table's `category` column and
-- by the backend recs/search path; the member's video-taste profile lives on
-- `members` (video_profile_summary / video_profile_embedding).
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
    -- The video's genre (video.tag) it was served under at this event; recs are
    -- grouped by this genre category (analytics / category-mix).
    category video_genre NOT NULL,
    -- The composite score at this serve: RAG cosine dominant, blended with gym
    -- relevance + popularity per the backend's weight settings.
    score DOUBLE PRECISION NOT NULL,
    recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Click signal: NULL = served but not clicked; set (service_role) when the
    -- member opens this recommendation. Feeds engagement / taste learning.
    clicked_at TIMESTAMPTZ,
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- The rec query's "already recommended" anti-join and the per-video last-serve
-- aggregate (MAX(recommended_at)) both filter by member and group by video.
CREATE INDEX idx_member_video_recs_member_video
    ON member_video_recs (member_id, video_id);
