-- Merge-upsert one pooled video from the git-tracked `videos/` YAML into the
-- shared pool (`make sync-gyms` → `scripts.import_yaml`).
--
-- THE WHOLE `DO UPDATE SET` BLOCK IS GUARDED, and for one reason: the `videos/`
-- YAML pool is LEGACY. It was written by the old standalone scraper, so a large
-- share of its rows carry NULL/empty where the live pipeline now carries paid,
-- expensive data — 4,084 files carry `tag: null`, 4,040 carry `transcript: null`,
-- every file carries an empty `channel_avatar_url`, and 22,831 carry the weaker
-- `@handle`-form `channel_url`. This import is re-run on EVERY `make sync-gyms`,
-- so an unguarded `= EXCLUDED.…` would silently wipe the worker's enrich-stage
-- tags, the Apify transcripts (real money), the accumulated source queries and the
-- best-across-scrapes relevance on every single sync.
--
-- The policy is NOT invented here: it MIRRORS the worker's own merge-upsert,
-- `src/worker/sql/worker_upsert_video.sql`, column for column — that file is the
-- canonical statement of which columns a re-ingest may overwrite. Keep the two in
-- agreement; if the worker's semantics change, change these with them.
INSERT INTO video (
    video_id, url, title, description, thumbnail_url,
    channel_name, channel_url, channel_avatar_url,
    view_count, like_count, duration_seconds,
    tag, disciplines, source_queries, relevance_index,
    transcript_error, transcript
)
VALUES (
    :video_id, :url, :title, :description, :thumbnail_url,
    :channel_name, :channel_url, :channel_avatar_url,
    :view_count, :like_count, :duration_seconds,
    CAST(:tag AS video_genre), CAST(:disciplines AS jsonb),
    CAST(:source_queries AS jsonb), :relevance_index,
    :transcript_error, :transcript
)
ON CONFLICT (video_id) DO UPDATE SET
    url = EXCLUDED.url,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    thumbnail_url = EXCLUDED.thumbnail_url,
    channel_name = EXCLUDED.channel_name,
    -- The two channel columns are GUARDED: this import must never DEGRADE a
    -- better stored value. The `videos/` YAML pool is legacy — its rows carry
    -- the weaker `@handle`-form channel_url and an always-empty
    -- channel_avatar_url — while the worker's own scrape
    -- (`src/worker/sql/worker_upsert_video.sql`) writes the canonical
    -- `/channel/UC…` id-form URL, and the worker's avatar-resolve step (plus the
    -- backend's owner-added-video path) fills the avatar. Unguarded, every
    -- `make sync-gyms` would overwrite those good values with the legacy ones.
    channel_url = CASE
        -- An empty incoming URL never wins.
        WHEN EXCLUDED.channel_url = '' THEN video.channel_url
        -- Never downgrade a stored id-form URL to an incoming handle-form one.
        -- (The reverse — stored handle, incoming id — falls through to ELSE and
        -- IS applied: an upgrade is always allowed, only a downgrade is blocked.)
        WHEN video.channel_url LIKE '%/channel/%'
            AND EXCLUDED.channel_url NOT LIKE '%/channel/%'
        THEN video.channel_url
        ELSE EXCLUDED.channel_url
    END,
    -- Same empty-guard idiom the worker's upsert uses (an avatar we already
    -- have is never blanked by the YAML's empty string).
    channel_avatar_url = CASE
        WHEN EXCLUDED.channel_avatar_url <> ''
        THEN EXCLUDED.channel_avatar_url
        ELSE video.channel_avatar_url
    END,
    -- Counts + duration COALESCE the way the worker's upsert does: these are
    -- legitimately NULL on the incoming row (hidden stats, a live broadcast, or
    -- simply an old YAML file that never captured them), and a NULL must never
    -- blank a good stored number.
    view_count = COALESCE(EXCLUDED.view_count, video.view_count),
    like_count = COALESCE(EXCLUDED.like_count, video.like_count),
    duration_seconds = COALESCE(
        EXCLUDED.duration_seconds, video.duration_seconds
    ),
    -- tag / disciplines are DELIBERATELY ABSENT from this SET — exactly as in the
    -- worker's upsert. The enrich stage owns them: it pays for a multimodal call
    -- per video to derive the genre + disciplines. 4,084 legacy YAML files carry
    -- `tag: null`, so assigning EXCLUDED here would wipe a paid enrichment on
    -- every sync. They ARE still in the INSERT column list above, so a video the
    -- pool has never seen still lands with whatever the YAML knows.
    -- The surfacing queries UNION rather than replace, so a re-import never drops
    -- queries the worker accumulated from later scrapes (dedup via DISTINCT;
    -- COALESCE covers the both-empty case, where jsonb_agg returns NULL).
    source_queries = COALESCE(
        (
            SELECT jsonb_agg(DISTINCT q)
            FROM jsonb_array_elements(
                video.source_queries || EXCLUDED.source_queries
            ) AS q
        ),
        video.source_queries
    ),
    -- Keep the BEST (lowest) rank ever observed for this video, across the YAML
    -- pool and every worker scrape — the same LEAST the worker applies.
    relevance_index = LEAST(video.relevance_index, EXCLUDED.relevance_index),
    -- A stored transcript is kept, never replaced: transcripts come from paid
    -- Apify actor runs, and 4,040 legacy YAML files carry `transcript: null`. An
    -- incoming transcript is only adopted when we have none.
    transcript = COALESCE(video.transcript, EXCLUDED.transcript),
    -- The error only describes a MISSING transcript, so it tracks the column
    -- above: if we kept a stored transcript, keep its (absent) error too.
    transcript_error = CASE
        WHEN video.transcript IS NOT NULL THEN video.transcript_error
        ELSE EXCLUDED.transcript_error
    END
