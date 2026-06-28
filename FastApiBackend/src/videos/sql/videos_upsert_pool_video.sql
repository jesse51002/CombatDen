-- Upsert an owner-added video into the shared pool with its real (YouTube Data
-- API) metadata. A brand-new row is OWNED by this gym (gym_id set) and marked
-- added_via='manual' — a private, deletable custom video. On conflict we refresh
-- only metadata-less rows (title='') and NEVER touch gym_id / added_via — so
-- adding a video already in the shared pool leaves it shared + web_query (a later
-- removal will reject it, not delete it).
INSERT INTO video (
    video_id, url, title, thumbnail_url, channel_name, channel_url,
    channel_avatar_url, view_count, duration_seconds, relevance_index,
    gym_id, added_via
)
VALUES (
    :video_id, :url, :title, :thumbnail_url, :channel_name, :channel_url,
    :channel_avatar_url, :view_count, :duration_seconds, 0,
    CAST(:gym_id AS UUID), 'manual'
)
ON CONFLICT (video_id) DO UPDATE SET
    title = EXCLUDED.title,
    thumbnail_url = EXCLUDED.thumbnail_url,
    channel_name = EXCLUDED.channel_name,
    channel_url = EXCLUDED.channel_url,
    channel_avatar_url = EXCLUDED.channel_avatar_url,
    view_count = EXCLUDED.view_count,
    duration_seconds = EXCLUDED.duration_seconds
WHERE video.title = ''
