INSERT INTO gym_video_spec (
    gym_id, gym_type, short_videos_desc, short_avoid_desc,
    videos_desc, avoid_desc, imported_from, imported_at, updated_at
) VALUES (
    CAST(:gym_id AS UUID), CAST(:gym_type AS JSONB), :short_videos_desc, :short_avoid_desc,
    :videos_desc, :avoid_desc, :imported_from, now(), now()
)
ON CONFLICT (gym_id) DO UPDATE SET
    gym_type = EXCLUDED.gym_type,
    short_videos_desc = EXCLUDED.short_videos_desc,
    short_avoid_desc = EXCLUDED.short_avoid_desc,
    videos_desc = EXCLUDED.videos_desc,
    avoid_desc = EXCLUDED.avoid_desc,
    imported_from = EXCLUDED.imported_from,
    imported_at = EXCLUDED.imported_at,
    updated_at = now()
