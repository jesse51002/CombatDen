INSERT INTO video (
    video_id, url, title, description, thumbnail_url,
    channel_name, channel_url, channel_avatar_url,
    view_count, like_count, duration_seconds,
    tag, disciplines, source_queries, relevance_index,
    transcript_error, transcript
)
VALUES (
    :video_id, :url, :title, :description, :thumbnail_url,
    :channel_name, :channel_url, :channel_avatar_url,
    :view_count, :like_count, :duration_seconds,
    CAST(:tag AS video_genre), CAST(:disciplines AS jsonb),
    CAST(:source_queries AS jsonb), :relevance_index,
    :transcript_error, :transcript
)
ON CONFLICT (video_id) DO UPDATE SET
    url = EXCLUDED.url,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    thumbnail_url = EXCLUDED.thumbnail_url,
    channel_name = EXCLUDED.channel_name,
    channel_url = EXCLUDED.channel_url,
    channel_avatar_url = EXCLUDED.channel_avatar_url,
    view_count = EXCLUDED.view_count,
    like_count = EXCLUDED.like_count,
    duration_seconds = EXCLUDED.duration_seconds,
    tag = EXCLUDED.tag,
    disciplines = EXCLUDED.disciplines,
    source_queries = EXCLUDED.source_queries,
    relevance_index = EXCLUDED.relevance_index,
    transcript_error = EXCLUDED.transcript_error,
    transcript = EXCLUDED.transcript
