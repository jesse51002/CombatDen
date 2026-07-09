-- RAG sidecar for the shared video pool: one row per ENRICHED video. Written
-- by the VideoService worker's enrich stage — ONE multimodal LLM call per
-- video (thumbnail image + title/channel/description + transcript slice)
-- produces the genre tag + disciplines (written onto `video`) AND the prose
-- `summary` + `facets` stored here; the summary is then embedded.
--
-- Deliberately a sidecar (not columns on `video`): the ~6KB embedding vectors
-- stay out of every feed read, and enrichment is lazy — a pool video has NO
-- row here until some gym's run enriches it ("un-enriched videos are
-- invisible to RAG"). There is exactly ONE embedding kind: the SUMMARY
-- embedding (thumbnails carry signal that titles/transcripts miss, e.g.
-- music-only videos, gi vs no-gi) — no metadata-embedding tier, no backfill.
--
-- Consumers: the worker's Tier-2 scan-candidate probes (spec queries embedded,
-- cosine top-k over these rows) and the backend's member recs / semantic
-- search (rank within mood buckets).
CREATE TABLE video_rag (
    video_id TEXT NOT NULL
        CONSTRAINT pk_video_rag PRIMARY KEY
        CONSTRAINT fk_video_rag_video
            REFERENCES video(video_id) ON DELETE CASCADE,
    -- Prose content summary from the multimodal enrich call; includes visual
    -- attributes read off the thumbnail (e.g. gi vs no-gi, setting, vibe).
    summary TEXT NOT NULL,
    -- Structured attributes from the same call (free-shape object, e.g.
    -- {"gi": false, "setting": "competition", "skill_level": "beginner"}).
    facets JSONB NOT NULL DEFAULT '{}'
        CONSTRAINT video_rag_facets_is_object
            CHECK (jsonb_typeof(facets) = 'object'),
    -- Embedding of `summary`. The dimension is pinned to the embedding model
    -- (a cross-service contract: VideoService worker writes, FastApiBackend
    -- reads/queries — both pin the same model + dim in settings). Changing
    -- models is a one-way door: migration + full re-embed of this table AND
    -- members.video_profile_embedding.
    embedding vector(1536) NOT NULL,
    embedding_model TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- HNSW ANN index over the summary embeddings. The ~18.9k unique template videos
-- are enriched up front (the enrich-templates sidecar seeds video_rag on every
-- `make sync-gyms`), so the table crosses the ~10k exact-scan threshold from the
-- very first sync — without the index every feed / rec / funnel cosine query
-- would scan the whole table. `vector_cosine_ops` matches the `<=>` cosine
-- distance the Tier-2 probes and rec/search readers rank with.
CREATE INDEX idx_video_rag_embedding ON video_rag
    USING hnsw (embedding vector_cosine_ops);
