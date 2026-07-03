-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds the video-worker RAG surface: pgvector, a run status lifecycle on
-- video_run, two new video_cost_log execution types + a per-run FK, and four
-- new tables (video_rag, member_video_profile, member_video_recs,
-- video_worker_queue).
-- Mirrors schemas/_extensions.sql, video_rag.sql, member_video_profile.sql,
-- member_video_recs.sql, video_worker_queue.sql, video_run.sql (edited),
-- video_cost_log.sql (edited) and access_rules/video_rag.sql,
-- member_video_profile.sql, member_video_recs.sql, video_worker_queue.sql.
--
-- Existing live tables touched: video_run, video_cost_log (video_cost_log
-- already has legacy rows attributed to TEXT video_gym template slugs).

-- ============================================================
-- 1. pgvector extension — everything vector-typed below depends on it.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- ============================================================
-- 2. video_run: add the run status lifecycle
--    DEFAULT 'completed' deliberately marks every pre-existing run served.
-- ============================================================

CREATE TYPE video_run_status AS ENUM ('running', 'completed', 'failed');

ALTER TABLE video_run
    ADD COLUMN status video_run_status NOT NULL DEFAULT 'completed',
    ADD COLUMN finished_at TIMESTAMPTZ,
    ADD COLUMN error TEXT;

-- ============================================================
-- 3. video_execution_type: add 'enrich' and 'embed'
--    Postgres 15+: ADD VALUE is transaction-safe as long as the new values
--    are not USED in the same transaction — this migration never references
--    'enrich'/'embed' in a DML statement, so the simple ADD VALUE form is
--    used here (unlike the discount_duration_unit type-recreate, which had
--    to use its new 'cycle' value in the same transaction via an UPDATE).
-- ============================================================

ALTER TYPE video_execution_type ADD VALUE IF NOT EXISTS 'enrich';
ALTER TYPE video_execution_type ADD VALUE IF NOT EXISTS 'embed';

-- ============================================================
-- 4. video_cost_log: retype gym_id TEXT -> UUID (FK -> gyms), add
--    video_run_id. Order matters — preserve legacy attribution before the
--    column is retyped and its old FK dropped.
-- ============================================================

-- 4a. Preserve legacy attribution: fold the old TEXT video_gym slug into the
--     note before the column is retyped (legacy template slugs cannot map to
--     real gyms, but their spend + provenance must survive).
UPDATE video_cost_log
SET note = COALESCE(note || ' | ', '') || 'template:' || gym_id
WHERE gym_id IS NOT NULL;

-- 4b. Drop the old FK (TEXT gym_id -> video_gym).
ALTER TABLE video_cost_log DROP CONSTRAINT fk_video_cost_log_gym;

-- 4c. Drop the existing index on gym_id before the retype, for deterministic
--     recreation (the type change from TEXT to UUID is not binary-coercible,
--     so rely on an explicit drop + recreate rather than the automatic
--     index-rebuild path).
DROP INDEX idx_video_cost_log_gym;

-- 4d. Retype gym_id to UUID. Legacy template slugs cannot map to any real
--     gym, so every existing row's gym_id becomes NULL (its spend + the
--     'template:<slug>' note from step 4a are preserved).
ALTER TABLE video_cost_log
    ALTER COLUMN gym_id TYPE UUID USING NULL;

-- 4e. Add the new FK to gyms, same constraint name as before.
ALTER TABLE video_cost_log
    ADD CONSTRAINT fk_video_cost_log_gym
        FOREIGN KEY (gym_id) REFERENCES gyms(gym_id) ON DELETE SET NULL;

-- 4f. Recreate the gym_id index.
CREATE INDEX idx_video_cost_log_gym ON video_cost_log (gym_id);

-- 4g. New column: the worker run this spend belongs to (NULL for legacy rows
--     and spend outside a run).
ALTER TABLE video_cost_log
    ADD COLUMN video_run_id UUID
        CONSTRAINT fk_video_cost_log_run
            REFERENCES video_run(run_id) ON DELETE SET NULL;

CREATE INDEX idx_video_cost_log_run ON video_cost_log (video_run_id);

-- ============================================================
-- 5. New table: video_rag (RAG sidecar for enriched videos)
-- ============================================================

CREATE TABLE video_rag (
    video_id TEXT NOT NULL
        CONSTRAINT pk_video_rag PRIMARY KEY
        CONSTRAINT fk_video_rag_video
            REFERENCES video(video_id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    facets JSONB NOT NULL DEFAULT '{}'
        CONSTRAINT video_rag_facets_is_object
            CHECK (jsonb_typeof(facets) = 'object'),
    embedding vector(1536) NOT NULL,
    embedding_model TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE video_rag ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read summaries for visible videos"
    ON video_rag
    FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM video
            WHERE video.video_id = video_rag.video_id
            AND (
                video.gym_id IS NULL
                OR is_gym_employee(video.gym_id)
                OR EXISTS (
                    SELECT 1 FROM members
                    WHERE members.gym_id = video.gym_id
                    AND members.user_id = auth.uid()
                )
            )
        )
    );

REVOKE INSERT, UPDATE, DELETE ON TABLE video_rag FROM authenticated;

-- ============================================================
-- 6. New table: member_video_profile (declares mood_bucket)
-- ============================================================

CREATE TYPE mood_bucket AS ENUM ('teach', 'enjoy', 'inform', 'human', 'peak');

CREATE TABLE member_video_profile (
    member_id UUID NOT NULL
        CONSTRAINT fk_member_video_profile_member
            REFERENCES members(member_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL
        CONSTRAINT fk_member_video_profile_gym
            REFERENCES gyms(gym_id) ON DELETE CASCADE,
    bucket mood_bucket NOT NULL,
    profile_text TEXT NOT NULL,
    embedding vector(1536) NOT NULL,
    embedding_model TEXT NOT NULL,
    built_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_member_video_profile PRIMARY KEY (member_id, bucket),
    CONSTRAINT fk_member_video_profile_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

ALTER TABLE member_video_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members and gym staff can view video profiles"
    ON member_video_profile
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_video_profile.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_video_profile.gym_id)
    );

REVOKE INSERT, UPDATE, DELETE ON TABLE member_video_profile FROM authenticated;

-- ============================================================
-- 7. New table: member_video_recs (uses mood_bucket)
-- ============================================================

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
    bucket mood_bucket NOT NULL,
    score DOUBLE PRECISION NOT NULL,
    first_recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    times_recommended INTEGER NOT NULL DEFAULT 1
        CONSTRAINT member_video_recs_times_positive
            CHECK (times_recommended > 0),
    CONSTRAINT uq_member_video_recs_member_video UNIQUE (member_id, video_id),
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_member_video_recs_member ON member_video_recs (member_id);

ALTER TABLE member_video_recs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members and gym staff can view rec history"
    ON member_video_recs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_video_recs.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_video_recs.gym_id)
    );

REVOKE INSERT, UPDATE, DELETE ON TABLE member_video_recs FROM authenticated;

-- ============================================================
-- 8. New table: video_worker_queue (declares video_worker_reason)
-- ============================================================

CREATE TYPE video_worker_reason AS ENUM ('spec_update', 'manual');

CREATE TABLE video_worker_queue (
    gym_id UUID NOT NULL
        CONSTRAINT pk_video_worker_queue PRIMARY KEY
        CONSTRAINT fk_video_worker_queue_gym
            REFERENCES gyms(gym_id) ON DELETE CASCADE,
    reason video_worker_reason NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_video_worker_queue_requested
    ON video_worker_queue (requested_at);

ALTER TABLE video_worker_queue ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE video_worker_queue FROM authenticated;
