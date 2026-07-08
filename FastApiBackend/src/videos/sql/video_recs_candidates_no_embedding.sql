-- Fallback rec candidates for a member with NO video-taste embedding yet
-- (never built / build failed). Ranks the gym's SERVED feed by the composite
-- score WITHOUT the similarity term -- RAG enrichment is not required, so a
-- brand-new member still gets recs. Grouping into mood buckets happens in
-- Python (bucket_for_genre(v.tag)); this query does not filter by bucket.
-- Candidate set + already_recommended anti-join mirror video_recs_candidates.sql.
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
        mr.last_recommended_at AS last_recommended_at
    FROM gym_video_feed f
    JOIN video v ON v.video_id = f.video_id
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
    video_id, url, title, thumbnail_url, channel_name, channel_url,
    channel_avatar_url, view_count, duration_seconds, tag, relevance_index,
    already_recommended,
    (
        :w_rel * (1.0 / (1.0 + relevance_index))
        + :w_views * LEAST(LN(1 + COALESCE(view_count, 0)) / 20.0, 1.0)
    ) AS score
FROM scored
ORDER BY
    already_recommended ASC,
    last_recommended_at ASC NULLS FIRST,
    score DESC
LIMIT :candidate_limit
