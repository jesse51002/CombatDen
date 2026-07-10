-- SHARED candidate-set source for a gym's SERVED feed — the SINGLE source of
-- "what counts as served". Injected as the candidate_source template variable
-- (via load_sql) into BOTH videos_load_feed_page.sql (the paginated served feed +
-- member rec) and videos_load_feed_preview.sql (the per-genre "All" preview), so
-- the serve predicate lives in ONE place: change it here and every served read
-- agrees. It is the FROM + JOINs + candidate WHERE core only; each including
-- query supplies its own SELECT list, extra filters, and ordering around it.
--
-- Owner "Your videos" rows (video_run_id IS NULL) MERGED with the gym's latest
-- COMPLETED run, enriched-only (INNER JOIN video_rag — an accepted row with no
-- embedding is invisible until the worker enriches it), :scan_status selecting
-- 'accepted' (served) vs 'rejected' (the rejected list). Binds :gym_id and
-- :scan_status (both always supplied by every including query).
FROM gym_video_feed f
JOIN video v ON v.video_id = f.video_id
JOIN video_rag r ON r.video_id = v.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.scan_status = CAST(:scan_status AS gym_video_scan_status)
  AND (
    f.video_run_id IS NULL
    -- Serve the latest COMPLETED run only: a mid-flight 'running' run must never
    -- become "latest" or the feed would blank until it finishes.
    OR f.video_run_id = (
        SELECT run_id FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
        ORDER BY created_at DESC
        LIMIT 1)
  )
