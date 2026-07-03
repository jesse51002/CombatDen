-- The gym's owner-section "Your videos" ids (run-independent rows, video_run_id
-- NULL). These are enriched alongside the scan candidates so owner-added videos
-- always carry a summary embedding for the backend's rec / semantic-search reads.
SELECT video_id
FROM gym_video_feed
WHERE gym_id = CAST(:gym_id AS UUID)
  AND video_run_id IS NULL;
