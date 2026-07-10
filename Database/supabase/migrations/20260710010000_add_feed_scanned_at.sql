-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds `scanned_at TIMESTAMPTZ` (nullable) to `gym_video_feed` — the timestamp
-- the worker's scan step stamps every time it judges a feed row against the gym's
-- spec. The feed-learning re-scan compares a gym's latest 'feed_update'
-- gym_video_spec version's created_at against this per-row watermark: an
-- 'automatic' row whose scanned_at predates a settled feed_update is re-judged in
-- place against the new criteria, then re-stamped so it won't re-trigger for the
-- same feed_update. NULL until first scanned (a pre-existing row, or one the scan
-- has not reached yet). No default, no backfill needed — a NULL scanned_at reads
-- as '-infinity' in the re-scan comparison, so every existing row is eligible for
-- one re-scan against any future feed_update.
--
-- Mirrors schemas/gym_video_feed.sql.

ALTER TABLE gym_video_feed ADD COLUMN scanned_at TIMESTAMPTZ;
