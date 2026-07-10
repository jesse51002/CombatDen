-- Insert a gym's feed ids for one status, skipping any id not present in the pool
-- (FK-safe) and de-duplicating against existing rows. :video_ids is a text[].
INSERT INTO template_gym_feed (gym_id, video_id, status)
SELECT :gym_id, vid, CAST(:status AS template_gym_feed_status)
FROM unnest(CAST(:video_ids AS text[])) AS vid
WHERE EXISTS (SELECT 1 FROM video v WHERE v.video_id = vid)
ON CONFLICT (gym_id, video_id) DO UPDATE SET status = EXCLUDED.status
