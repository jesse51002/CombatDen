-- One gym assembled in a single round trip: the gym row plus its queries,
-- classes, rewards, and curated good/rejected feed ids (ordered by the pool's
-- relevance_index) as JSONB aggregates. Returns no rows when the gym is missing.
SELECT
    g.gym_id,
    g.gym_type,
    g.theme,
    g.short_videos_desc,
    g.short_avoid_desc,
    g.videos_desc,
    g.avoid_desc,
    g.has_classes,
    g.has_rewards,
    (
        SELECT coalesce(jsonb_agg(q.query), '[]'::jsonb)
        FROM video_gym_query q
        WHERE q.gym_id = g.gym_id
    ) AS queries,
    (
        SELECT coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'name', c.name,
                    'image_url', c.image_url,
                    'description', c.description,
                    'instructor_name', c.instructor_name,
                    'instructor_bio', c.instructor_bio,
                    'instructor_image_url', c.instructor_image_url
                )
                ORDER BY c.name
            ),
            '[]'::jsonb
        )
        FROM video_gym_class c
        WHERE c.gym_id = g.gym_id
    ) AS classes,
    (
        SELECT coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'title', r.title,
                    'image_url', r.image_url,
                    'price_label', r.price_label,
                    'points_cost', r.points_cost
                )
                ORDER BY r.points_cost
            ),
            '[]'::jsonb
        )
        FROM video_gym_reward r
        WHERE r.gym_id = g.gym_id
    ) AS rewards,
    (
        SELECT coalesce(jsonb_agg(s.video_id ORDER BY s.relevance_index, s.video_id), '[]'::jsonb)
        FROM (
            SELECT f.video_id, v.relevance_index
            FROM video_gym_feed f
            JOIN video v ON v.video_id = f.video_id
            WHERE f.gym_id = g.gym_id AND f.status = 'good'
        ) s
    ) AS good_video_ids,
    (
        SELECT coalesce(jsonb_agg(s.video_id ORDER BY s.relevance_index, s.video_id), '[]'::jsonb)
        FROM (
            SELECT f.video_id, v.relevance_index
            FROM video_gym_feed f
            JOIN video v ON v.video_id = f.video_id
            WHERE f.gym_id = g.gym_id AND f.status = 'rejected'
        ) s
    ) AS rejected_video_ids
FROM video_gym g
WHERE g.gym_id = :gym_id
