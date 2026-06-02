INSERT INTO video_gym (
    gym_id, gym_type, theme,
    short_videos_desc, short_avoid_desc, videos_desc, avoid_desc,
    has_classes, has_rewards
)
VALUES (
    :gym_id, CAST(:gym_type AS jsonb), :theme,
    :short_videos_desc, :short_avoid_desc, :videos_desc, :avoid_desc,
    :has_classes, :has_rewards
)
ON CONFLICT (gym_id) DO UPDATE SET
    gym_type = EXCLUDED.gym_type,
    theme = EXCLUDED.theme,
    short_videos_desc = EXCLUDED.short_videos_desc,
    short_avoid_desc = EXCLUDED.short_avoid_desc,
    videos_desc = EXCLUDED.videos_desc,
    avoid_desc = EXCLUDED.avoid_desc,
    has_classes = EXCLUDED.has_classes,
    has_rewards = EXCLUDED.has_rewards
