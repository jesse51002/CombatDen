-- The shared video pool: one flat row per de-duplicated YouTube video. Machine-
-- written by the scraper (merge-upsert) and classify pass; never hand-authored —
-- EXCEPT owner-added custom videos, which a gym adds by hand (one YouTube link)
-- and which carry that gym's `gym_id` (the row is then owned by / private to that
-- gym). The multi-value fields (disciplines, source_queries) are JSONB string
-- arrays on the row itself — no junction tables. The `video_genre` enum (single
-- content genre) is declared here.

CREATE TYPE video_genre AS ENUM (
    'educational', 'analysis', 'entertainment', 'news', 'interview',
    'vlog', 'professional', 'clips', 'memes'
);

-- How a video entered the system, and — load-bearing — whether it may be
-- DELETED: 'web_query' (found via the scrape's search queries; shared, removal =
-- reject only) vs 'manual' (an owner pasted the link; gym-owned, removal = hard
-- delete). Lives on the video (not the feed) because removability is a property
-- of the video itself.
CREATE TYPE video_source AS ENUM ('web_query', 'manual');

CREATE TABLE video (
    video_id TEXT NOT NULL
        CONSTRAINT video_id_format CHECK (video_id ~ '^[A-Za-z0-9_-]+$'),  -- YouTube id
    url TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',  -- carried for data checks, not rendered
    thumbnail_url TEXT NOT NULL,
    channel_name TEXT NOT NULL,
    channel_url TEXT NOT NULL,
    channel_avatar_url TEXT NOT NULL DEFAULT '',  -- empty post-scrape; backfilled at serve time
    view_count INTEGER,        -- NULL when stats hidden
    like_count INTEGER,        -- NULL when likes hidden
    duration_seconds INTEGER,  -- NULL for live broadcasts
    tag video_genre,           -- single genre; NULL until the classify pass runs
    -- The disciplines this video fits (classification, NOT approval). A JSONB
    -- array of discipline strings, e.g. ["kettlebell", "rowing"]. Empty until tagged.
    disciplines JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT video_disciplines_is_array CHECK (jsonb_typeof(disciplines) = 'array'),
    -- The literal search query/queries that surfaced this video — tracing only.
    source_queries JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT video_source_queries_is_array CHECK (jsonb_typeof(source_queries) = 'array'),
    relevance_index INTEGER NOT NULL
        CONSTRAINT video_relevance_index_nonneg CHECK (relevance_index >= 0),
    transcript_error TEXT,
    transcript TEXT,           -- full caption text (large); NULL when none / fetch failed
    -- The owning gym for an owner-added CUSTOM video (private to it). NULL for a
    -- shared, web-query/scraped video (the default — the pool is gym-agnostic
    -- except for these custom rows). Removing a custom video deletes its pool row
    -- (it's owned); a shared row is never deleted by a gym.
    gym_id UUID
        CONSTRAINT fk_video_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    -- How it entered + whether it can be deleted (see the enum). 'web_query' for
    -- scraped rows (the default); 'manual' for owner-added custom rows.
    added_via video_source NOT NULL DEFAULT 'web_query',
    CONSTRAINT pk_video PRIMARY KEY (video_id)
);

CREATE INDEX idx_video_tag ON video (tag);
-- A gym's own custom videos (partial — most rows are shared, gym_id NULL).
CREATE INDEX idx_video_gym ON video (gym_id) WHERE gym_id IS NOT NULL;
-- The scan candidate slice: videos whose disciplines overlap a gym's, via
--   WHERE disciplines ?| ARRAY[...gym disciplines...]
CREATE INDEX idx_video_disciplines ON video USING GIN (disciplines);
