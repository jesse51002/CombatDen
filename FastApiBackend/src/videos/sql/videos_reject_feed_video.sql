-- MANUAL reject of a web_query video in the gym's LATEST scan run (the genre
-- feed): flip it to 'rejected' with curation_type='manual', the optional reason,
-- and the time. The row is kept (the rejected list); a later "keep" flips
-- scan_status back, leaving this audit as history.
UPDATE gym_video_feed
SET scan_status = 'rejected',
    curation_type = 'manual',
    curation_reason = :reason,
    rejected_at = now(),
    curated_at = now()
WHERE gym_id = CAST(:gym_id AS UUID)
  AND video_id = :video_id
  AND video_run_id = (
      SELECT run_id FROM video_run
      WHERE gym_id = CAST(:gym_id AS UUID)
      ORDER BY created_at DESC
      LIMIT 1)
