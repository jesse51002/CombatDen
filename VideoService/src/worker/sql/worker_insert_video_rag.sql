-- Insert one enriched video's RAG sidecar row: the prose summary, free-shape
-- facets, and the summary embedding (serialised as the pgvector text form
-- '[f1,f2,...]', cast to vector). ON CONFLICT DO NOTHING is a safety net — the
-- enrich set already excludes ids that have a row.
INSERT INTO video_rag (video_id, summary, facets, embedding, embedding_model)
VALUES (
    :video_id,
    :summary,
    CAST(:facets AS JSONB),
    CAST(:embedding AS vector),
    :embedding_model
)
ON CONFLICT (video_id) DO NOTHING;
