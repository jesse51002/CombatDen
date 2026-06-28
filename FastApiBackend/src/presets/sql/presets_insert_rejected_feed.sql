-- Copy a template's rejected video ids into the gym's feed under :run_id as
-- automatically-rejected rows. Only ids present in the shared pool are inserted.
-- The whole template rejection list is seeded so the gym's rejected view mirrors
-- the scan's full keep/drop verdict.
INSERT INTO gym_video_feed (
    gym_id, video_id, video_run_id, scan_status, rejection_type, rejected_at
)
SELECT
    CAST(:gym_id AS UUID),
    v.video_id,
    CAST(:run_id AS UUID),
    'rejected',
    'automatic',
    now()
FROM video v
WHERE v.video_id = ANY(:ids)
ON CONFLICT (video_run_id, video_id) WHERE video_run_id IS NOT NULL DO NOTHING
