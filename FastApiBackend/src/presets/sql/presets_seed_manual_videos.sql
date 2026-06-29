-- Demo seed: drop the given video ids into the gym's owner "Your videos" section
-- (video_run_id NULL, always served) so it isn't empty after an import. They also
-- live in the run (genre rows) — a harmless dup. Only seeded when the owner
-- section is currently empty (the caller checks).
INSERT INTO gym_video_feed (gym_id, video_id, video_run_id, scan_status)
SELECT CAST(:gym_id AS UUID), v.video_id, NULL, 'accepted'
FROM video v
WHERE v.video_id = ANY(:ids)
ON CONFLICT (gym_id, video_id) WHERE video_run_id IS NULL DO NOTHING
