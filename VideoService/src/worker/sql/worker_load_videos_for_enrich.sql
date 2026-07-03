-- The fields the enrich call needs, for the videos to enrich. thumbnail_url feeds
-- the multimodal image part; the rest build the text prompt.
SELECT
    video_id,
    title,
    channel_name,
    description,
    thumbnail_url,
    duration_seconds,
    transcript
FROM video
WHERE video_id = ANY(:ids);
