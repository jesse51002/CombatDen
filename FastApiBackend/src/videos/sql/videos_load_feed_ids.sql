-- One gym's served feed ids, ordered by the pool's relevance_index. gym_video_feed
-- is lean (no status column): every row is a served video, so there is no
-- good/rejected split here — presence == served.
SELECT f.video_id
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
ORDER BY v.relevance_index, v.video_id
