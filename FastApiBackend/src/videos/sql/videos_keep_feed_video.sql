-- "Keep" a rejected video in the gym's LATEST run: flip it back to 'accepted',
-- retaining rejected_at as history. Captures the optional owner-supplied reason
-- (curation_reason) which the feed-learning refiner uses to widen the spec's
-- include criteria. Sets curation_type = 'manual' (owner explicitly kept it via
-- the UI). Bind param :accept_reason maps to curation_reason (the CRM sends
-- accept_reason; the param name is kept stable so the caller is unchanged).
UPDATE gym_video_feed
SET scan_status = 'accepted',
    curation_type = 'manual',
    curation_reason = :accept_reason,
    curated_at = now()
WHERE gym_id = CAST(:gym_id AS UUID)
  AND video_id = :video_id
  -- Only an actually-rejected row is a real "keep" (un-reject): keeping an
  -- already-accepted video is a no-op that must curate 0 rows (rowcount = 0) so
  -- the caller fires no wasted feed-learning refine.
  AND scan_status <> 'accepted'
  -- Target the run currently being SERVED (latest COMPLETED): an owner's keep
  -- during an in-flight run must curate the served feed, not the 'running' one.
  AND video_run_id = (
      SELECT run_id FROM video_run
      WHERE gym_id = CAST(:gym_id AS UUID)
        AND status = 'completed'
      ORDER BY created_at DESC
      LIMIT 1)
