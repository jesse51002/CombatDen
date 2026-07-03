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
  -- Target the run currently being SERVED (latest COMPLETED): an owner's keep
  -- during an in-flight run must curate the served feed, not the 'running' one.
  AND video_run_id = (
      SELECT run_id FROM video_run
      WHERE gym_id = CAST(:gym_id AS UUID)
        AND status = 'completed'
      ORDER BY created_at DESC
      LIMIT 1)
