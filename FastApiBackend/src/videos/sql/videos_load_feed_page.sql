-- Paginated real-gym video feed page.
-- Joins gym_video_feed → video, applies feed and tag filters, orders by
-- relevance, and returns the page plus the total match count in one round-trip.
--
-- Parameters:
--   :gym_id             UUID of the gym
--   :scan_status        'accepted' | 'rejected'  (gym_video_scan_status enum)
--   :owner              true  → owner section (video_run_id IS NULL);
--                       false → gym's latest scan run
--   :video_type         a single video_genre string or NULL (exact tag match)
--   :filter_big_group   'educational' | 'entertainment' | NULL (big-group filter)
--   :educational_genres list[str]  the genre strings that map to EDUCATIONAL
--   :limit              page size
--   :offset             0-based start index
--
-- NOTE: COUNT(*) OVER() returns 0 rows (and therefore total=0) when the
-- requested offset is beyond the last matching row. Callers should not
-- request pages beyond the total returned by the first request.
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
    COUNT(*) OVER() AS total
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.scan_status = CAST(:scan_status AS gym_video_scan_status)
  AND (
    (:owner AND f.video_run_id IS NULL)
    OR (NOT :owner AND f.video_run_id = (
        SELECT run_id FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
        ORDER BY created_at DESC
        LIMIT 1))
  )
  AND (
    CAST(:video_type AS text) IS NULL
    OR v.tag::text = CAST(:video_type AS text)
  )
  AND (
    CAST(:filter_big_group AS text) IS NULL
    OR (
      CAST(:filter_big_group AS text) = 'educational'
      AND v.tag IS NOT NULL
      AND v.tag::text = ANY(:educational_genres)
    )
    OR (
      CAST(:filter_big_group AS text) = 'entertainment'
      AND v.tag IS NOT NULL
      AND NOT (v.tag::text = ANY(:educational_genres))
    )
  )
ORDER BY v.relevance_index, v.video_id
LIMIT :limit OFFSET :offset
