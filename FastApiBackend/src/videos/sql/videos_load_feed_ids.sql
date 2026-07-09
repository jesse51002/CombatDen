-- A gym's served feed ids, in pool-relevance order — the SAME candidate set the
-- unified feed page serves so the "All" preview agrees with the served feed:
-- owner "Your videos" rows (video_run_id IS NULL) MERGED with the gym's latest
-- COMPLETED run, enriched-only (INNER JOIN video_rag), :scan_status selecting
-- 'accepted' (served) or 'rejected' (the rejected list). No owner param.
SELECT f.video_id
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
JOIN video_rag r ON r.video_id = v.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.scan_status = CAST(:scan_status AS gym_video_scan_status)
  AND (
    f.video_run_id IS NULL
    -- Serve the latest COMPLETED run only: a mid-flight 'running' run must
    -- never become "latest" or the feed would blank until it finishes.
    OR f.video_run_id = (
        SELECT run_id FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
        ORDER BY created_at DESC
        LIMIT 1)
  )
ORDER BY v.relevance_index, v.video_id
