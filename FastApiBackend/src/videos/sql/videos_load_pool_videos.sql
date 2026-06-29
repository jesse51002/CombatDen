-- Load the named pooled videos (a gym's feed ids). Disciplines is aliased to
-- gym_type so the row maps straight onto the card model. The caller restores feed
-- order and skips any id with no row.
SELECT
    video_id,
    url,
    title,
    description,
    thumbnail_url,
    channel_name,
    channel_url,
    channel_avatar_url,
    view_count,
    like_count,
    duration_seconds,
    tag,
    disciplines AS gym_type,
    source_queries,
    relevance_index,
    transcript_error,
    transcript
FROM video
WHERE video_id = ANY(:ids)
