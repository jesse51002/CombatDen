-- "Keep" a rejected video in the gym's LATEST run: flip it back to 'accepted',
-- KEEPING the reject audit (rejection_type / reject_reason / rejected_at) as the
-- history of the last rejection.
UPDATE gym_video_feed
SET scan_status = 'accepted',
    curated_at = now()
WHERE gym_id = CAST(:gym_id AS UUID)
  AND video_id = :video_id
  AND video_run_id = (
      SELECT run_id FROM video_run
      WHERE gym_id = CAST(:gym_id AS UUID)
      ORDER BY created_at DESC
      LIMIT 1)
