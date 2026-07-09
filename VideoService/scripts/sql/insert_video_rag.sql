-- Upsert one template RAG row from the enrich sidecar into video_rag. FK-safe:
-- the INSERT ... SELECT only fires when the pooled video exists (the pool loads
-- first in import_yaml), so a stray id is skipped rather than raising. ON CONFLICT
-- DO NOTHING SEEDS a fresh DB and never clobbers a live worker enrichment with the
-- template baseline. Embedding arrives as the pgvector text literal '[f1,f2,...]'
-- (cast to vector), facets as a JSON string (cast to jsonb) — mirroring the
-- worker's worker_insert_video_rag.sql. Runs as an executemany batch.
INSERT INTO video_rag (video_id, summary, facets, embedding, embedding_model)
SELECT
    :video_id,
    :summary,
    CAST(:facets AS JSONB),
    CAST(:embedding AS vector),
    :embedding_model
WHERE EXISTS (SELECT 1 FROM video v WHERE v.video_id = :video_id)
ON CONFLICT (video_id) DO NOTHING;
