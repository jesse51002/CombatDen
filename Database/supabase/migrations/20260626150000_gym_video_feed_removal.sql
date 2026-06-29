-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds the gym_video_feed_removal append-only log table: one video removed from
-- a gym's served feed per row, capturing which video, who removed it, when, and
-- why (so the curation signal survives the DELETE on gym_video_feed). No views
-- are touched; no enums are created.
-- Mirrors schemas/gym_video_feed_removal.sql and
-- access_rules/gym_video_feed_removal.sql.

-- ============================================================
-- 1. New table: gym_video_feed_removal
-- ============================================================

CREATE TABLE gym_video_feed_removal (
    removal_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_gym_video_feed_removal PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_feed_removal_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    -- The removed pool video id. No FK to `video`: this is a historical log that
    -- must outlive any later garbage-collection of the shared pool row.
    video_id TEXT NOT NULL,
    -- Why the owner removed it (free text); NULL when they gave no reason.
    reason TEXT,
    -- The Supabase auth user id (JWT `sub`) of whoever removed it; NULL if absent.
    removed_by UUID,
    removed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Read a gym's removal history (and the scan's "don't re-add" lookup).
CREATE INDEX idx_gym_video_feed_removal_gym ON gym_video_feed_removal (gym_id);

-- ============================================================
-- 2. RLS + policy + REVOKE for gym_video_feed_removal
-- ============================================================

ALTER TABLE gym_video_feed_removal ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's removal history.
CREATE POLICY "Gym employees can view feed removals"
    ON gym_video_feed_removal
    FOR SELECT
    USING (is_gym_employee(gym_video_feed_removal.gym_id));

-- Append-only log written by the backend (service_role) when an owner removes a
-- video; clients never write it, and even the backend never updates or deletes a
-- row (it is a permanent record).
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_feed_removal FROM authenticated;
