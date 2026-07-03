-- Tier 2 scan candidates for ONE query probe: the discipline-filtered enriched
-- videos whose summary embedding is nearest this query's embedding (cosine, the
-- `<=>` operator), excluding the tier-1 ids already chosen. The caller runs one
-- probe per spec-query vector and unions the results client-side, keeping each
-- video's best (smallest) distance. Only enriched videos (a video_rag row) can
-- match — un-enriched videos are invisible to RAG by design.
SELECT r.video_id, (r.embedding <=> CAST(:vec AS vector)) AS distance
FROM video_rag r
JOIN video v ON v.video_id = r.video_id
WHERE jsonb_exists_any(v.disciplines, CAST(:disciplines AS TEXT[]))
  AND NOT (r.video_id = ANY(:exclude_ids))
ORDER BY r.embedding <=> CAST(:vec AS vector)
LIMIT :top_k;
