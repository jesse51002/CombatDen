-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds an optional free-text accept/keep reason to `gym_video_feed`, mirroring
-- the existing reject audit (reject_reason / rejected_at / rejection_type).
-- When an owner un-rejects / keeps a video they may supply a reason; this
-- column captures it so the feed-learning refiner can use it when refining the
-- spec's include criteria.
--
-- The column is nullable (no back-fill needed; no existing keeps carried a
-- reason before this migration). The reject audit is unchanged.
-- Mirrors schemas/gym_video_feed.sql.

ALTER TABLE gym_video_feed
    ADD COLUMN accept_reason TEXT;
