-- The member's next SINGLE recommendation WITHIN ONE genre category, ranked by
-- PURE cosine similarity to the member's video-taste embedding
-- (members.video_profile_embedding). The caller rotates categories
-- (video_rec_category_rotation) and runs this once per category until a pick is
-- found; :category is the current genre. LIMIT 1 -- the surface serves one video.
--
-- Candidate set = the gym's SERVED feed, EXACTLY as videos_load_feed_ids defines
-- it: accepted rows of the gym's latest COMPLETED run PLUS the owner's
-- run-independent rows (video_run_id IS NULL). The completed-status filter on the
-- latest-run subselect mirrors the feed serve path so a mid-flight 'running' run
-- never leaks in. (This is the same candidate set the rec has always used -- NOT
-- the feed page's exclusive owner flag; the owner-vs-run question is separate.)
--
-- Ranking is PURE cosine distance (video_rag.embedding <=> the member embedding),
-- un-enriched videos (no video_rag row -> NULL distance) falling to the end. When
-- the member has NO embedding (:member_embedding bound NULL) the CASE collapses
-- the distance term to 0 for every row, so the whole set orders by the secondary
-- keys (gym relevance, then video_id) instead. Already-served videos are excluded
-- (NOT EXISTS over member_video_recs) so each call advances to a fresh pick.
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
    v.relevance_index
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
LEFT JOIN video_rag r ON r.video_id = v.video_id
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
  AND v.tag = CAST(:category AS video_genre)
  AND NOT EXISTS (
    SELECT 1 FROM member_video_recs mr
    WHERE mr.member_id = CAST(:member_id AS UUID)
      AND mr.video_id = v.video_id
  )
ORDER BY
    CASE
        WHEN CAST(:member_embedding AS text) IS NULL THEN 0
        ELSE (r.embedding <=> CAST(:member_embedding AS vector))
    END ASC NULLS LAST,
    v.relevance_index,
    v.video_id
LIMIT 1
