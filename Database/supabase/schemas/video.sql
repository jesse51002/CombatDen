-- The shared video pool: one flat row per de-duplicated YouTube video. Machine-
-- written by the scraper (merge-upsert) and classify pass; never hand-authored.
-- The multi-value fields (disciplines, source_queries) are JSONB string arrays on
-- the row itself — no junction tables. The `video_genre` enum (single content
-- genre) is declared here.

CREATE TYPE video_genre AS ENUM (
    'educational', 'analysis', 'entertainment', 'news', 'interview',
    'vlog', 'professional', 'clips', 'memes'
);

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
    CONSTRAINT pk_video PRIMARY KEY (video_id)
);

CREATE INDEX idx_video_tag ON video (tag);
-- The scan candidate slice: videos whose disciplines overlap a gym's, via
--   WHERE disciplines ?| ARRAY[...gym disciplines...]
CREATE INDEX idx_video_disciplines ON video USING GIN (disciplines);
