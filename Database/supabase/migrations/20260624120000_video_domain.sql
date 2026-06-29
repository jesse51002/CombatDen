-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds three new prod-side video tables (gym_video_spec, gym_video_feed,
-- gym_video_query) and two nullable columns (gyms.theme_design_id,
-- gym_rewards.price_label). No views are touched; no enums are created.
-- Mirrors schemas/gym_video_spec.sql, gym_video_feed.sql, gym_video_query.sql,
-- and the updated schemas/gyms.sql + gym_rewards.sql.

-- ============================================================
-- 1. New table: gym_video_spec
-- ============================================================

CREATE TABLE gym_video_spec (
    gym_id UUID NOT NULL
        CONSTRAINT pk_gym_video_spec PRIMARY KEY
        CONSTRAINT fk_gym_video_spec_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    -- The gym's discipline(s) as a JSONB string array; gym_type[0] is primary.
    gym_type JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT gym_video_spec_type_is_array CHECK (jsonb_typeof(gym_type) = 'array'),
    short_videos_desc TEXT,
    short_avoid_desc TEXT,
    videos_desc TEXT NOT NULL DEFAULT '',
    avoid_desc TEXT NOT NULL DEFAULT '',
    -- Provenance: the video_gym template slug a preset import copied this from.
    imported_from TEXT,
    imported_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. New table: gym_video_feed
-- ============================================================

CREATE TABLE gym_video_feed (
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_feed_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_gym_video_feed_video REFERENCES video(video_id) ON DELETE CASCADE,
    CONSTRAINT pk_gym_video_feed PRIMARY KEY (gym_id, video_id)
);

-- Serve a gym's feed (the join to `video` supplies relevance ordering + cards).
CREATE INDEX idx_gym_video_feed_gym ON gym_video_feed (gym_id);

-- ============================================================
-- 3. New table: gym_video_query
-- ============================================================

CREATE TABLE gym_video_query (
    query_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_query_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    query TEXT NOT NULL CONSTRAINT gym_video_query_nonempty CHECK (query <> ''),
    CONSTRAINT pk_gym_video_query PRIMARY KEY (query_id)
);

CREATE INDEX idx_gym_video_query_gym ON gym_video_query (gym_id);

-- ============================================================
-- 4. Nullable column additions to existing tables
-- ============================================================

ALTER TABLE gyms
    ADD COLUMN theme_design_id TEXT;

ALTER TABLE gym_rewards
    ADD COLUMN price_label VARCHAR;

-- ============================================================
-- 5. RLS + policies + REVOKEs for gym_video_spec
-- ============================================================

ALTER TABLE gym_video_spec ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's video spec.
CREATE POLICY "Gym employees can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (is_gym_employee(gym_video_spec.gym_id));

-- Members can view their gym's video spec (member app showcase).
CREATE POLICY "Members can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_spec.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_spec FROM authenticated;

-- ============================================================
-- 6. RLS + policies + REVOKEs for gym_video_feed
-- ============================================================

ALTER TABLE gym_video_feed ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's feed.
CREATE POLICY "Gym employees can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (is_gym_employee(gym_video_feed.gym_id));

-- Members can view their gym's feed (member app video surfaces).
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

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_feed FROM authenticated;

-- ============================================================
-- 7. RLS + policies + REVOKEs for gym_video_query
-- ============================================================

ALTER TABLE gym_video_query ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's search queries.
CREATE POLICY "Gym employees can view video queries"
    ON gym_video_query
    FOR SELECT
    USING (is_gym_employee(gym_video_query.gym_id));

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_query FROM authenticated;
