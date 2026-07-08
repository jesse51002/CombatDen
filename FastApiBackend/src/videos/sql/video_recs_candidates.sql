-- A member's ranked video recommendations, RANKED ONCE against the member's
-- single video-taste embedding (members.video_profile_embedding). Grouping by
-- the video's genre category (v.tag) happens in Python AFTER this query -- this
-- SQL does not filter or group by genre.
--
-- Candidate set = the gym's SERVED feed, EXACTLY as videos_load_feed_ids
-- defines it: accepted rows of the gym's latest COMPLETED run PLUS the owner's
-- run-independent rows (video_run_id IS NULL). The completed-status filter on
-- the latest-run subselect mirrors the feed serve path so a mid-flight
-- 'running' run never leaks in.
--
-- Only ENRICHED videos are eligible: the JOIN to video_rag drops any pool video
-- without a summary embedding (RAG is lazy -- un-enriched videos are invisible
-- to the similarity ranking).
--
-- Ranking:
--   similarity = 1 - cosine_distance(video summary embedding, member embedding)
--   score      = w_sim*similarity + w_rel*(1/(1+relevance_index))
--                + w_views*min(ln(1+views)/20, 1)
-- ORDER BY hard-partitions UNRECOMMENDED videos first (freshness), then:
--   within unrecommended  -> score DESC
--   within recommended    -> last serve ASC (oldest first), score DESC
--
-- member_video_recs is an append-only serve log (one row per serve), so the
-- per-video last-serve time is MAX(recommended_at), pre-aggregated per video in
-- the member_recs CTE below; its presence in the LEFT JOIN flags
-- already_recommended (global per member, any genre). A generous
-- :candidate_limit only bounds the working set; grouping by genre + per-category
-- slicing happen in Python.
WITH member_recs AS (
    SELECT video_id, MAX(recommended_at) AS last_recommended_at
    FROM member_video_recs
    WHERE member_id = CAST(:member_id AS UUID)
    GROUP BY video_id
),
scored AS (
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
        (mr.video_id IS NOT NULL) AS already_recommended,
        mr.last_recommended_at AS last_recommended_at,
        (1 - (r.embedding <=> CAST(:member_embedding AS vector))) AS similarity
    FROM gym_video_feed f
    JOIN video v ON v.video_id = f.video_id
    JOIN video_rag r ON r.video_id = v.video_id
    LEFT JOIN member_recs mr ON mr.video_id = v.video_id
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
      AND v.tag IS NOT NULL
)
SELECT
    video_id,
    url,
    title,
    thumbnail_url,
    channel_name,
    channel_url,
    channel_avatar_url,
    view_count,
    duration_seconds,
    tag,
    relevance_index,
    already_recommended,
    similarity,
    (
        :w_sim * similarity
        + :w_rel * (1.0 / (1.0 + relevance_index))
        + :w_views * LEAST(LN(1 + COALESCE(view_count, 0)) / 20.0, 1.0)
    ) AS score
FROM scored
ORDER BY
    already_recommended ASC,
    last_recommended_at ASC NULLS FIRST,
    score DESC
LIMIT :candidate_limit
