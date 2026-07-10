-- A real customer gym's live video spec — APPEND-VERSIONED. Each confirmed change
-- INSERTs a new immutable version row; readers take the LATEST per gym via the
-- `gym_video_spec_latest` view, never the raw table. This is the PRODUCTION
-- counterpart of the slug-keyed `template_gym` template catalog (`template_gym*` holds
-- the 76 hand-authored templates the preset import copies FROM).
--
-- The long videos_desc/avoid_desc pair is the scan criteria the (separate) batch
-- job judges candidates against; the short pair is display-only. `queries` is the
-- gym's YouTube search list as a JSONB string array (it collapses the old separate
-- `gym_video_query` table). `source` records what produced the version, and
-- `imported_from` records the template slug a preset import seeded it from (NULL
-- once agent/hand-authored).

-- What produced a spec version: the feed-curation learning refine (folds recent
-- reject/readd signals into improved criteria + queries), an admin/agent edit, or
-- a system action (preset import / automation).
CREATE TYPE gym_video_spec_source AS ENUM (
    'feed_update', 'admin_update', 'system_update'
);

CREATE TABLE gym_video_spec (
    spec_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_gym_video_spec PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_spec_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    -- The gym's discipline(s) as a JSONB string array; gym_type[0] is primary.
    gym_type JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT gym_video_spec_type_is_array CHECK (jsonb_typeof(gym_type) = 'array'),
    short_videos_desc TEXT,
    short_avoid_desc TEXT,
    videos_desc TEXT NOT NULL DEFAULT '',
    avoid_desc TEXT NOT NULL DEFAULT '',
    -- The gym's YouTube search queries as a JSONB string array (collapses the old
    -- gym_video_query table). Seeds the (separate) batch job's scrape.
    queries JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT gym_video_spec_queries_is_array CHECK (jsonb_typeof(queries) = 'array'),
    -- What produced this version.
    source gym_video_spec_source NOT NULL,
    -- Provenance: the template_gym template slug a preset import copied this from.
    imported_from TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Take a gym's latest version fast (the serve / agent / worker read path).
CREATE INDEX idx_gym_video_spec_gym_created
    ON gym_video_spec (gym_id, created_at DESC);

-- The latest spec version per gym — every reader selects from THIS, never the
-- raw append-only table. security_invoker so the base table's RLS (employee /
-- member SELECT policies) applies to whoever queries the view.
CREATE VIEW gym_video_spec_latest
WITH (security_invoker = true)
AS
SELECT DISTINCT ON (gym_id) *
FROM gym_video_spec
ORDER BY gym_id, created_at DESC, spec_id DESC;

-- Safety net: migration diffing can strip security_invoker from CREATE VIEW.
ALTER VIEW gym_video_spec_latest SET (security_invoker = true);
