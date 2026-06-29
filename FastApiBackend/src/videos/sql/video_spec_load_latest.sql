-- The gym's LATEST video-config version (the spec is append-only versioned; read
-- through the gym_video_spec_latest view). Returns no rows when the gym has no
-- spec authored yet.
SELECT
    gym_id,
    gym_type,
    short_videos_desc,
    short_avoid_desc,
    videos_desc,
    avoid_desc,
    queries,
    source,
    imported_from,
    created_at
FROM gym_video_spec_latest
WHERE gym_id = CAST(:gym_id AS UUID)
