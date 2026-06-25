-- A template's approved feed ids (slug-keyed), in the pool's relevance order.
-- The public template feed/preview hydrate these from the shared `video` pool.
-- Mirrors videos_load_feed_ids.sql but reads the slug-keyed template feed.
SELECT f.video_id
FROM video_gym_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = :video_gym_id AND f.status = 'good'
ORDER BY v.relevance_index, v.video_id
