-- Insert one fresh scan verdict for this run. curation_type is always
-- 'automatic' (the scan, not the owner, placed it); a rejected row stamps
-- rejected_at (passed as now() from the caller, NULL for accepted). ON CONFLICT
-- DO NOTHING so a carried row (inserted first) always wins over a fresh verdict
-- for the same video.
INSERT INTO gym_video_feed (
    gym_id, video_id, video_run_id, scan_status, curation_type, rejected_at
)
VALUES (
    CAST(:gym_id AS UUID),
    :video_id,
    CAST(:run_id AS UUID),
    CAST(:scan_status AS gym_video_scan_status),
    'automatic',
    :rejected_at
)
ON CONFLICT (video_run_id, video_id)
    WHERE video_run_id IS NOT NULL DO NOTHING;
