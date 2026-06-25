-- A real gym's live video spec — one row per gym. Returns no rows when the gym
-- has no spec authored yet.
SELECT
    gym_id,
    gym_type,
    short_videos_desc,
    short_avoid_desc,
    videos_desc,
    avoid_desc,
    imported_from,
    imported_at
FROM gym_video_spec
WHERE gym_id = CAST(:gym_id AS UUID)
