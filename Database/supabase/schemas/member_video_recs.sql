-- Recommendation history: an APPEND-ONLY event log — one row per (member,
-- video) SERVE. There is no stored score and NO already-served anti-join, and
-- nothing is hard-partitioned. Freshness is enforced at READ time by the unified
-- feed query (FastApiBackend/src/videos/sql/videos_load_feed_page.sql) as a
-- σ-scaled DECAYED WATCH PENALTY: for each candidate the feed sums
-- power(0.5, age_seconds / half_life) over this member's prior serves of that
-- video (a just-served video ≈ 1, an old serve ≈ 0; half-life 7d) and nudges the
-- video FARTHER by penalty_units·bump_fraction·sigma. So a served video is pushed
-- back immediately after and drifts forward again over the following week, rather
-- than being excluded or hard-partitioned. "Already recommended" is global per
-- member (not per-category): a video served under any genre category counts.
--
-- Recs are grouped by the video's genre CATEGORY (its `video.tag` — the
-- `video_genre` enum created in schemas/video.sql). There is no separate
-- abstraction over the genre: `category` stores the video's actual genre and
-- RAG ranks WITHIN a category. Consumed by this table's `category` column and
-- by the backend rec + personalized-feed read path; the member's video-taste
-- profile lives on `members` (video_profile_summary / video_profile_embedding).
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
    recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Click signal: NULL = served but not clicked; set (service_role) when the
    -- member opens this recommendation. Feeds engagement / taste learning.
    clicked_at TIMESTAMPTZ,
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- Backs the feed's decayed-watch-penalty lookup: for each candidate the feed
-- sums this member's decayed prior serves of one video — a correlated aggregate
-- filtered by member and video — so the index keys on exactly that pair.
CREATE INDEX idx_member_video_recs_member_video
    ON member_video_recs (member_id, video_id);
