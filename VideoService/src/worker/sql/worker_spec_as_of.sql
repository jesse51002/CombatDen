-- The spec version that was LATEST as of :as_of (the previous completed run's
-- created_at). The spec is append-only, so "what the criteria were at that run"
-- is just the newest version created at or before that instant. Compared against
-- the current latest to decide whether criteria changed (fresh vs incremental).
SELECT videos_desc, avoid_desc
FROM gym_video_spec
WHERE gym_id = CAST(:gym_id AS UUID)
  AND created_at <= :as_of
ORDER BY created_at DESC, spec_id DESC
LIMIT 1;
