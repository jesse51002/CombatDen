-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds the gym_video_feed_source enum and the gym_video_feed.added_via column,
-- which records how a video entered a real gym's served feed: 'web_query' (the
-- scrape's search queries — the bulk path the preset/template import copies from)
-- or 'manual' (owner pasted a YouTube link). Existing rows backfill to 'web_query'
-- via the column DEFAULT — they all arrived through imports. No views are touched;
-- no enums are retired.
-- Mirrors the updated schemas/gym_video_feed.sql.

-- ============================================================
-- 1. New enum: gym_video_feed_source
-- ============================================================

CREATE TYPE gym_video_feed_source AS ENUM ('web_query', 'manual');

-- ============================================================
-- 2. New column: gym_video_feed.added_via
-- ============================================================

ALTER TABLE gym_video_feed
    ADD COLUMN added_via gym_video_feed_source NOT NULL DEFAULT 'web_query';
