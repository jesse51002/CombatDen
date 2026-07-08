-- Semantic video search within a gym's SERVED feed. Same candidate set as the
-- rec query (accepted rows of the latest COMPLETED run + the owner's
-- run-independent rows), but with NO genre filter — a free-text query is
-- embedded once and ranked by cosine similarity to each video's summary
-- embedding. Only enriched videos (those with a video_rag row) are searchable.
SELECT
    v.video_id,
    v.url,
    v.title,
    v.thumbnail_url,
    v.channel_name,
    v.channel_url,
    v.channel_avatar_url,
    v.view_count,
    v.duration_seconds,
    v.tag,
    v.relevance_index,
    (1 - (r.embedding <=> CAST(:query_embedding AS vector))) AS similarity
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
JOIN video_rag r ON r.video_id = v.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.scan_status = 'accepted'
  AND (
    f.video_run_id IS NULL
    OR f.video_run_id = (
        SELECT run_id FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
        ORDER BY created_at DESC
        LIMIT 1)
  )
ORDER BY r.embedding <=> CAST(:query_embedding AS vector) ASC
LIMIT :limit
