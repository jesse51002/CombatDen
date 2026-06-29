-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Reshapes gym_video_spec into an APPEND-VERSIONED model and folds the separate
-- gym_video_query table into it as a JSONB queries array:
--   * gym_video_spec_source (NEW enum): what produced a spec version
--     ('feed_update' | 'admin_update' | 'system_update').
--   * gym_video_spec (RESHAPED): spec_id UUID becomes the PK (gym_id stays as a
--     plain NOT NULL FK); queries JSONB string array collapses gym_video_query;
--     source + created_at are added; imported_at + updated_at are dropped.
--   * gym_video_spec_latest (NEW view): security_invoker read path — latest row
--     per gym via DISTINCT ON (gym_id) ORDER BY created_at DESC, spec_id DESC.
--   * gym_video_query (DROPPED): its rows are folded into gym_video_spec.queries
--     before the drop; its RLS policy and index go with the table.
--   * gym_video_feed: curated_at TIMESTAMPTZ column added (nullable).
-- Mirrors schemas/gym_video_spec.sql, schemas/gym_video_feed.sql, and
-- access_rules/gym_video_spec.sql.
--
-- DATA PRESERVED: existing spec rows become each gym's first version
-- (source='system_update'); their YouTube queries are aggregated from
-- gym_video_query into the new queries JSONB array before the table is dropped
-- (gyms with no query rows get '[]'). imported_from is kept as provenance.
-- Pool (video) and feed (gym_video_feed) data are untouched.

-- ============================================================
-- 1. New enum: what produced a spec version
-- ============================================================

CREATE TYPE gym_video_spec_source AS ENUM (
    'feed_update', 'admin_update', 'system_update'
);

-- ============================================================
-- 2. Add new columns to gym_video_spec (nullable for backfill)
-- ============================================================

ALTER TABLE gym_video_spec
    ADD COLUMN spec_id    UUID,
    ADD COLUMN queries    JSONB,
    ADD COLUMN source     gym_video_spec_source,
    ADD COLUMN created_at TIMESTAMPTZ;

-- ============================================================
-- 3. Backfill: each existing row becomes its gym's first spec
--    version. spec_id: unique UUID per row (UPDATE evaluates
--    gen_random_uuid() per row, unlike ADD COLUMN DEFAULT).
--    queries: aggregate from gym_video_query ordered for
--    determinism; COALESCE to '[]' for gyms with zero queries.
--    created_at: reuse imported_at if present, else now().
--    source: 'system_update' — these rows came from the preset
--    import, the sole existing writer.
-- ============================================================

UPDATE gym_video_spec s
SET
    spec_id    = gen_random_uuid(),
    source     = 'system_update',
    created_at = COALESCE(s.imported_at, now()),
    queries    = COALESCE(
                    (SELECT jsonb_agg(q.query ORDER BY q.query)
                     FROM gym_video_query q
                     WHERE q.gym_id = s.gym_id),
                    '[]'::jsonb
                 );

-- ============================================================
-- 4. Enforce NOT NULL + defaults, add queries array check,
--    then swap the PK from gym_id to spec_id
-- ============================================================

ALTER TABLE gym_video_spec
    ALTER COLUMN spec_id    SET NOT NULL,
    ALTER COLUMN spec_id    SET DEFAULT gen_random_uuid(),
    ALTER COLUMN queries    SET NOT NULL,
    ALTER COLUMN queries    SET DEFAULT '[]'::jsonb,
    ALTER COLUMN source     SET NOT NULL,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT now();

ALTER TABLE gym_video_spec
    ADD CONSTRAINT gym_video_spec_queries_is_array
        CHECK (jsonb_typeof(queries) = 'array');

-- Swap PK: drop gym_id as PK (its NOT NULL + FK constraints stay),
-- promote spec_id. The FK constraint fk_gym_video_spec_gym is unaffected.
ALTER TABLE gym_video_spec DROP CONSTRAINT pk_gym_video_spec;
ALTER TABLE gym_video_spec ADD CONSTRAINT pk_gym_video_spec PRIMARY KEY (spec_id);

-- ============================================================
-- 5. Drop old columns (imported_at is now folded into
--    created_at; updated_at is replaced by the append-versioned
--    pattern — each change is a new row, never an UPDATE)
-- ============================================================

ALTER TABLE gym_video_spec
    DROP COLUMN imported_at,
    DROP COLUMN updated_at;

-- ============================================================
-- 6. Index for the latest-per-gym read path
-- ============================================================

CREATE INDEX idx_gym_video_spec_gym_created
    ON gym_video_spec (gym_id, created_at DESC);

-- ============================================================
-- 7. Latest-version view (security_invoker so the base table's
--    RLS — employee + member SELECT policies — applies to the
--    caller, not the view definer)
-- ============================================================

CREATE VIEW gym_video_spec_latest
WITH (security_invoker = true)
AS
SELECT DISTINCT ON (gym_id) *
FROM gym_video_spec
ORDER BY gym_id, created_at DESC, spec_id DESC;

-- Safety net: migration diffing can strip security_invoker from
-- a recreated view.
ALTER VIEW gym_video_spec_latest SET (security_invoker = true);

-- Append-only via service_role; clients read via the view, never write it.
REVOKE INSERT, UPDATE, DELETE ON gym_video_spec_latest FROM authenticated;

-- ============================================================
-- 8. Drop gym_video_query (queries folded into spec above;
--    its SELECT policy and idx_gym_video_query_gym are dropped
--    automatically with the table)
-- ============================================================

DROP TABLE gym_video_query;

-- ============================================================
-- 9. gym_video_feed: add curated_at (nullable — NULL means the
--    row has never been manually curated, e.g. automatic-scan
--    rows; manual owner reject/keep/readd bumps this to now())
-- ============================================================

ALTER TABLE gym_video_feed
    ADD COLUMN curated_at TIMESTAMPTZ;
