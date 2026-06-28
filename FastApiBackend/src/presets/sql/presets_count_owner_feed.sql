-- How many videos are already in the gym's owner "Your videos" section
-- (video_run_id NULL). The import seeds the section only when this is 0.
SELECT count(*) FROM gym_video_feed
WHERE gym_id = CAST(:gym_id AS UUID) AND video_run_id IS NULL
