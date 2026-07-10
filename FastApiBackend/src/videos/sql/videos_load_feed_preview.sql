-- The "All" preview: a few videos per genre in ONE query. Same served candidate
-- set as the feed page (the candidate_source core is injected from the shared
-- videos_feed_candidate_source.sql), restricted to tagged videos, then windowed
-- per genre: ROW_NUMBER() ranks each genre's videos by pool relevance and only
-- the first :per_tag survive, so no genre is starved and no full-feed load +
-- Python slice is needed.
--
-- Parameters:
--   :gym_id       UUID of the gym
--   :scan_status  'accepted' | 'rejected'  (gym_video_scan_status enum)
--   :per_tag      max videos kept per genre section
--
-- Section order = first appearance in feed order (relevance_index, video_id):
-- FIRST_VALUE over the per-genre window pins each genre's leading video, and the
-- final ORDER BY groups every genre's rows contiguously behind that leader. The
-- caller groups the ordered rows into GymFeedSection list, preserving this order.
WITH candidates AS (
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
        (f.video_run_id IS NULL) AS owner_added
    {candidate_source}
      AND v.tag IS NOT NULL
),
ranked AS (
    SELECT
        candidates.*,
        ROW_NUMBER() OVER w AS rn,
        FIRST_VALUE(relevance_index) OVER w AS tag_first_rel,
        FIRST_VALUE(video_id) OVER w AS tag_first_vid
    FROM candidates
    WINDOW w AS (PARTITION BY tag ORDER BY relevance_index, video_id)
)
SELECT
    video_id,
    url,
    title,
    description,
    thumbnail_url,
    channel_name,
    channel_url,
    channel_avatar_url,
    view_count,
    like_count,
    duration_seconds,
    tag,
    gym_type,
    source_queries,
    relevance_index,
    transcript_error,
    transcript,
    owner_added
FROM ranked
WHERE rn <= :per_tag
ORDER BY tag_first_rel, tag_first_vid, relevance_index, video_id
