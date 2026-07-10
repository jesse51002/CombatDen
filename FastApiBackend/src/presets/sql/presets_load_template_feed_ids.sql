-- A template's feed ids for the given status (slug-keyed), in the pool's
-- relevance order. status='good' is the served feed; status='rejected' backs the
-- admin rejected-review surface. The public template feed/preview hydrate these
-- from the shared `video` pool. (The lean real-gym gym_video_feed has no status —
-- only the template_gym_feed keeps the good/rejected split.)
SELECT f.video_id
FROM template_gym_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = :video_gym_id
  AND f.status = CAST(:status AS template_gym_feed_status)
ORDER BY v.relevance_index, v.video_id
