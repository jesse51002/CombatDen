-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds the video-worker RAG surface and generalizes the cost ledger:
--   * pgvector extension
--   * a run status lifecycle on video_run
--   * a generic cost_log (replaces video_cost_log): source + run_id + gym_id +
--     stage + cost_usd + model; matched back to its source table via (source, run_id)
--   * video_rag (per-video RAG sidecar)
--   * the member video-taste RAG profile columns on members
--   * member_video_recs (per-serve rec history, grouped by the video's genre
--     category, with a clicked_at click signal)
--   * member_activities.activity_type promoted from free-text VARCHAR to the
--     member_activity_type enum
-- The worker has no queue table — it derives which gym to run from run/spec/
-- curation timestamps (see VideoService/src/worker/sql/worker_select_due_gym.sql).
-- Mirrors schemas/_extensions.sql, cost_log.sql, video_rag.sql,
-- member_video_recs.sql, members.sql, member_activities.sql, video_run.sql
-- (edited) and access_rules/cost_log.sql, video_rag.sql, member_video_recs.sql.
--
-- The DB is reset+reseeded fresh at apply time: video_cost_log and the RAG
-- tables are EMPTY and member_activities is empty (seed runs after), so the
-- clean cost_log drop/recreate and the activity_type cast are safe.

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
-- 3. cost_log: a generic spend ledger that REPLACES video_cost_log.
--    The old table + its enum are used only here, and the DB is reseeded
--    fresh, so a clean drop/recreate beats a data-preserving retype. `source`
--    names the producing system (only 'video' today; extensible) and
--    (source, run_id) matches a cost row back to its source table's run.
-- ============================================================

DROP TABLE IF EXISTS video_cost_log CASCADE;
DROP TYPE IF EXISTS video_execution_type;

CREATE TYPE cost_stage AS ENUM (
    'search', 'transcript', 'tag', 'enrich', 'embed', 'scan'
);
CREATE TYPE cost_source AS ENUM ('video');

CREATE TABLE cost_log (
    entry_id UUID NOT NULL DEFAULT uuid_generate_v4()
        CONSTRAINT pk_cost_log PRIMARY KEY,
    source cost_source NOT NULL,
    run_id TEXT,
    gym_id UUID
        CONSTRAINT fk_cost_log_gym REFERENCES gyms(gym_id) ON DELETE SET NULL,
    stage cost_stage NOT NULL,
    model TEXT,
    cost_usd DOUBLE PRECISION NOT NULL DEFAULT 0,
    breakdown JSONB NOT NULL DEFAULT '{}',
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cost_log_gym ON cost_log (gym_id);
CREATE INDEX idx_cost_log_run ON cost_log (run_id);
CREATE INDEX idx_cost_log_source ON cost_log (source);

-- Cost rows are service-role-written and matched back to their source table
-- via (source, run_id). Public SELECT (cost visibility); no client writes.
ALTER TABLE cost_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read cost log"
    ON cost_log
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE INSERT, UPDATE, DELETE ON TABLE cost_log FROM authenticated;

-- ============================================================
-- 4. New table: video_rag (RAG sidecar for enriched videos)
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
-- 5. The member video-taste RAG profile on members.
--    The profile lives on members (not a sidecar table): one summary + one
--    embedding per member, built lazily by the backend (service_role) — all
--    nullable, null until first built. The embedding is pinned to
--    settings.video_embedding_dim (cross-service contract; same model + dim as
--    video_rag.embedding).
-- ============================================================

ALTER TABLE members
    ADD COLUMN video_profile_summary TEXT,
    ADD COLUMN video_profile_embedding vector(1536),
    ADD COLUMN video_profile_embedding_model TEXT,
    ADD COLUMN video_profile_built_at TIMESTAMPTZ;

-- ============================================================
-- 6. New table: member_video_recs (grouped by the video's genre category —
--    video_genre, the type of video.tag, created in the baseline migration)
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
    -- The video's genre (video.tag) it was served under at this event; recs are
    -- grouped by this genre category (analytics / category-mix).
    category video_genre NOT NULL,
    score DOUBLE PRECISION NOT NULL,
    recommended_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Click signal: NULL = served but not clicked; set when the member opens it.
    clicked_at TIMESTAMPTZ,
    CONSTRAINT fk_member_video_recs_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

-- Append-only event log: one row per serve. "Already recommended" anti-join +
-- per-video MAX(recommended_at) last-serve aggregate both key on (member, video).
CREATE INDEX idx_member_video_recs_member_video
    ON member_video_recs (member_id, video_id);

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
-- 7. member_activities.activity_type: free-text VARCHAR -> enum.
--    The table is empty at migration time (seed runs after), so the cast is
--    safe; the existing readers compare activity_type = 'rank_changed' as a
--    text literal and keep working against the enum column.
-- ============================================================

CREATE TYPE member_activity_type AS ENUM (
    'class_attended', 'rank_changed', 'video_clicked'
);

ALTER TABLE member_activities
    ALTER COLUMN activity_type TYPE member_activity_type
    USING activity_type::member_activity_type;
