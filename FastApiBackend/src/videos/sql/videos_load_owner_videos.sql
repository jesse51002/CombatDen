-- The gym owner's UNGATED "Your videos" management listing. Unlike the served
-- feed (videos_load_feed_page.sql, which INNER JOINs video_rag), an owner-added
-- video must be visible the INSTANT it is added — before enrichment — so this
-- LEFT JOINs video_rag and exposes `enriched` for the CRM to badge "processing…".
-- Owner-section rows only (video_run_id IS NULL), accepted, newest add first.
--
-- Parameters:
--   :gym_id  UUID of the gym
--   :limit   page size
--   :offset  0-based start index
--
-- NOTE: COUNT(*) OVER() returns 0 rows (total=0) when offset is past the last row.
SELECT
    v.video_id,
    v.url,
    v.title,
    v.description,
    v.thumbnail_url,
    v.channel_name,
    v.channel_url,
    v.channel_avatar_url,
    v.view_count,
    v.like_count,
    v.duration_seconds,
    v.tag,
    v.disciplines AS gym_type,
    v.source_queries,
    v.relevance_index,
    v.transcript_error,
    v.transcript,
    TRUE AS owner_added,
    (r.video_id IS NOT NULL) AS enriched,
    COUNT(*) OVER() AS total
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
LEFT JOIN video_rag r ON r.video_id = v.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.video_run_id IS NULL
  AND f.scan_status = 'accepted'
ORDER BY f.curated_at DESC NULLS LAST, v.video_id
LIMIT :limit OFFSET :offset
