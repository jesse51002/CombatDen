-- A gym's served feed ids, in pool-relevance order. :owner true → the owner
-- "Your videos" section (video_run_id IS NULL, always served); false → the gym's
-- LATEST scan run. :scan_status selects 'accepted' (served) or 'rejected' (the
-- rejected list).
SELECT f.video_id
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.scan_status = CAST(:scan_status AS gym_video_scan_status)
  AND (
    (:owner AND f.video_run_id IS NULL)
    -- Serve the latest COMPLETED run only: a mid-flight 'running' run must
    -- never become "latest" or the feed would blank until it finishes.
    OR (NOT :owner AND f.video_run_id = (
        SELECT run_id FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
        ORDER BY created_at DESC
        LIMIT 1))
  )
ORDER BY v.relevance_index, v.video_id
