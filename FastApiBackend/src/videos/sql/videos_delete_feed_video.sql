-- Hard-delete a MANUAL video's owner-section feed row (manual videos live only
-- in the owner section, video_run_id NULL). The owned pool row is deleted
-- separately. Idempotent.
DELETE FROM gym_video_feed
WHERE gym_id = CAST(:gym_id AS UUID)
  AND video_id = :video_id
  AND video_run_id IS NULL
