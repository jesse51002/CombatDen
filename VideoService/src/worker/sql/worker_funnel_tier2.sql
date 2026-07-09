-- Tier 2 scan candidates for ONE query probe: the discipline-filtered enriched
-- videos whose summary embedding is nearest this query's embedding (cosine, the
-- `<=>` operator), excluding the tier-1 ids already chosen. The caller runs one
-- probe per spec-query vector and unions the results client-side, keeping each
-- video's best (smallest) distance. Only enriched videos (a video_rag row) can
-- match — un-enriched videos are invisible to RAG by design.
--
-- The distance + ORDER BY cast the 3072-dim embedding to `halfvec` so this probe
-- uses the `idx_video_rag_embedding` HNSW index (built on `embedding::halfvec(3072)`
-- — pgvector can't HNSW a `vector` past 2000 dims). Half precision costs ~0 recall;
-- the pool is the whole video table, so the ANN index is what keeps this scalable.
SELECT
    r.video_id,
    (r.embedding::halfvec(3072) <=> CAST(:vec AS halfvec(3072))) AS distance
FROM video_rag r
JOIN video v ON v.video_id = r.video_id
WHERE jsonb_exists_any(v.disciplines, CAST(:disciplines AS TEXT[]))
  AND NOT (r.video_id = ANY(:exclude_ids))
ORDER BY r.embedding::halfvec(3072) <=> CAST(:vec AS halfvec(3072))
LIMIT :top_k;
