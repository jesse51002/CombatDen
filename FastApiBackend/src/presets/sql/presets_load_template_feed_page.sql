-- Paginated template video feed page.
-- Joins template_gym_feed → video, applies status and tag filters, orders by
-- relevance, and returns the page plus the total match count in one round-trip.
--
-- Parameters:
--   :video_gym_id       slug-keyed template id (template_gym.gym_id)
--   :status             'good' | 'rejected'  (template_gym_feed_status enum)
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
FROM template_gym_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = :video_gym_id
  AND f.status = CAST(:status AS template_gym_feed_status)
  AND (
    :video_type IS NULL
    OR v.tag::text = :video_type
  )
  AND (
    :filter_big_group IS NULL
    OR (
      :filter_big_group = 'educational'
      AND v.tag IS NOT NULL
      AND v.tag::text = ANY(:educational_genres)
    )
    OR (
      :filter_big_group = 'entertainment'
      AND v.tag IS NOT NULL
      AND NOT (v.tag::text = ANY(:educational_genres))
    )
  )
ORDER BY v.relevance_index, v.video_id
LIMIT :limit OFFSET :offset
