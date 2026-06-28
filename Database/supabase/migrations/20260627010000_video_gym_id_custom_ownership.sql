-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds video.gym_id (nullable UUID FK → gyms ON DELETE CASCADE): marks a
-- custom, owner-added video's owning gym. NULL means the row is a shared /
-- web-query / scraped video (the default — the pool is gym-agnostic except for
-- these custom rows). Existing rows all get gym_id = NULL automatically (all
-- shared). Adds a partial index on gym_id for the non-NULL custom-video slice
-- (most rows are shared, so the partial keeps the index small).
-- Tightens the video pool's read RLS: the old "Public can read videos" policy
-- (which granted SELECT to every row regardless of gym_id) is replaced by
-- "Read shared videos or own gym's custom videos" — shared rows (gym_id IS NULL)
-- stay fully public to anon + authenticated; custom rows (gym_id set) are
-- visible only to that gym's staff and its members. anon has no auth.uid(), so
-- anon sees only shared rows in practice.
-- No views, enums, or other tables are touched.
-- Mirrors the updated schemas/video.sql and access_rules/video.sql.

-- ============================================================
-- 1. New column: video.gym_id
-- ============================================================

ALTER TABLE video
    ADD COLUMN gym_id UUID
        CONSTRAINT fk_video_gym REFERENCES gyms(gym_id) ON DELETE CASCADE;

-- ============================================================
-- 2. Partial index: custom-video slice
-- ============================================================

CREATE INDEX idx_video_gym ON video (gym_id) WHERE gym_id IS NOT NULL;

-- ============================================================
-- 3. Replace RLS SELECT policy
-- ============================================================

DROP POLICY "Public can read videos" ON video;

CREATE POLICY "Read shared videos or own gym's custom videos"
    ON video
    FOR SELECT
    TO anon, authenticated
    USING (
        gym_id IS NULL
        OR is_gym_employee(gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = video.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- ============================================================
-- 4. Revoke client updates on the new ownership column
-- ============================================================

-- video_id (PK) was already REVOKE'd in the original schema load; only the new
-- gym_id column needs revoking here.
REVOKE UPDATE (gym_id) ON TABLE video FROM authenticated;
