-- Copy a template's good video ids into the gym's feed under :run_id (accepted).
-- Only ids present in the shared pool are inserted. Sets curation_type =
-- 'automatic' because the scan/import (not the owner) placed these rows.
INSERT INTO gym_video_feed (gym_id, video_id, video_run_id, scan_status, curation_type)
SELECT CAST(:gym_id AS UUID), v.video_id, CAST(:run_id AS UUID), 'accepted', 'automatic'
FROM video v
WHERE v.video_id = ANY(:ids)
ON CONFLICT (video_run_id, video_id) WHERE video_run_id IS NOT NULL DO NOTHING
