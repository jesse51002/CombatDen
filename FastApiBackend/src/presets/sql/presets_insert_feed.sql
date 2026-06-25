INSERT INTO gym_video_feed (gym_id, video_id)
SELECT CAST(:gym_id AS UUID), v.video_id
FROM video v
WHERE v.video_id = ANY(:ids)
ON CONFLICT (gym_id, video_id) DO NOTHING
