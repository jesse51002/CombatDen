-- Add a video to the gym's owner "Your videos" section (video_run_id NULL,
-- always served, scan_status accepted). Idempotent on the owner-section unique
-- index (gym_id, video_id) WHERE video_run_id IS NULL. Sets curation_type =
-- 'manual' because the owner is explicitly adding it via the UI.
INSERT INTO gym_video_feed (gym_id, video_id, video_run_id, scan_status, curation_type, curated_at)
VALUES (CAST(:gym_id AS UUID), :video_id, NULL, 'accepted', 'manual', now())
ON CONFLICT (gym_id, video_id) WHERE video_run_id IS NULL DO UPDATE
    SET curated_at = now()
