-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Reworks the real-gym video feed into a versioned, scan-status model:
--   * video.added_via (NEW, enum video_source): renamed from the old
--     gym_video_feed_source enum and MOVED onto the video — it marks how a video
--     entered + whether it can be DELETED (web_query = reject only, manual = hard
--     delete). Existing custom rows (gym_id set) backfill to 'manual'.
--   * video_run (NEW table): one row per scan/import that built a gym's feed.
--   * gym_video_feed (REBUILT): surrogate feed_id PK, + video_run_id (NULL = the
--     owner "Your videos" section, always served), + scan_status
--     (accepted | rejected) + reject_* audit. added_via is gone (now on video).
--   * gym_video_feed_removal (DROPPED): the rejected row + reject_reason replace
--     the separate removal log.
-- Mirrors schemas/video.sql, video_run.sql, gym_video_feed.sql and
-- access_rules/video_run.sql, gym_video_feed.sql.
--
-- DESTRUCTIVE: gym_video_feed is dropped + recreated, so a gym's feed rows are
-- lost (re-import a preset to repopulate). The shared `video` pool is preserved.

-- ============================================================
-- 1. Drop the removal log (replaced by reject_reason on the feed row)
-- ============================================================

DROP TABLE gym_video_feed_removal;

-- ============================================================
-- 2. Drop the old feed (frees the old added_via column + its enum)
-- ============================================================

DROP TABLE gym_video_feed;

-- ============================================================
-- 3. Rename the freed enum and move added_via onto the video
-- ============================================================

ALTER TYPE gym_video_feed_source RENAME TO video_source;

ALTER TABLE video
    ADD COLUMN added_via video_source NOT NULL DEFAULT 'web_query';
-- Custom owner-added videos (gym-owned) are 'manual'; everything else stays
-- 'web_query' (the default).
UPDATE video SET added_via = 'manual' WHERE gym_id IS NOT NULL;

-- ============================================================
-- 4. New table: video_run (versioned scan/import runs)
-- ============================================================

CREATE TABLE video_run (
    run_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_video_run PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_video_run_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_video_run_gym_created ON video_run (gym_id, created_at DESC);

ALTER TABLE video_run ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view video runs"
    ON video_run
    FOR SELECT
    USING (is_gym_employee(video_run.gym_id));

REVOKE INSERT, UPDATE, DELETE ON TABLE video_run FROM authenticated;

-- ============================================================
-- 5. Rebuilt table: gym_video_feed (run-scoped + scan_status)
-- ============================================================

CREATE TYPE gym_video_scan_status AS ENUM ('accepted', 'rejected');
CREATE TYPE gym_video_rejection_type AS ENUM ('automatic', 'manual');

CREATE TABLE gym_video_feed (
    feed_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_gym_video_feed PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_feed_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_gym_video_feed_video REFERENCES video(video_id) ON DELETE CASCADE,
    video_run_id UUID
        CONSTRAINT fk_gym_video_feed_run REFERENCES video_run(run_id) ON DELETE CASCADE,
    scan_status gym_video_scan_status NOT NULL DEFAULT 'accepted',
    -- Reject audit = the LAST rejection, retained across re-acceptance (an
    -- accepted row may still carry it). Only rule: a currently-rejected row must
    -- say how it was rejected.
    rejection_type gym_video_rejection_type,
    reject_reason TEXT,
    rejected_at TIMESTAMPTZ,
    CONSTRAINT rejection_type_when_rejected
        CHECK (scan_status = 'accepted' OR rejection_type IS NOT NULL)
);

CREATE UNIQUE INDEX uq_gym_video_feed_run_video
    ON gym_video_feed (video_run_id, video_id)
    WHERE video_run_id IS NOT NULL;
CREATE UNIQUE INDEX uq_gym_video_feed_owner_video
    ON gym_video_feed (gym_id, video_id)
    WHERE video_run_id IS NULL;
CREATE INDEX idx_gym_video_feed_gym ON gym_video_feed (gym_id);

-- ============================================================
-- 6. RLS for the rebuilt gym_video_feed (recreated with the table)
-- ============================================================

ALTER TABLE gym_video_feed ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (is_gym_employee(gym_video_feed.gym_id));

CREATE POLICY "Members can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_feed.gym_id
            AND members.user_id = auth.uid()
        )
    );

REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_feed FROM authenticated;
