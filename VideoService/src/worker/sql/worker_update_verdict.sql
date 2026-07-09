-- Write ONE scan verdict onto a pending feed row: flip scan_status to
-- accepted/rejected. The scan_status = 'pending' guard means a manual verdict (or
-- a prior automatic verdict) is NEVER overwritten — only a still-pending row is
-- updated; curation_type stays 'automatic'. A rejected row stamps rejected_at
-- (now() from the caller, NULL for accepted). Keyed by (gym_id, video_id,
-- video_run_id) so it targets exactly this run's row. Runs once per verdicted
-- video (executemany).
UPDATE gym_video_feed
   SET scan_status = CAST(:verdict AS gym_video_scan_status),
       rejected_at = :rejected_at
 WHERE gym_id = CAST(:gym_id AS UUID)
   AND video_id = :video_id
   AND video_run_id = CAST(:video_run_id AS UUID)
   AND scan_status = 'pending';
