-- Delete the shared-pool row for a video ONLY when it's a custom video owned by
-- THIS gym (gym_id matches). A shared (web-query / scraped) row — gym_id NULL or
-- another gym's — never matches, so it is left untouched. No-op when not owned.
DELETE FROM video
WHERE video_id = :video_id
  AND gym_id = CAST(:gym_id AS UUID)
