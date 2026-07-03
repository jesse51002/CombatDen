-- Merge-upsert one freshly-scraped video into the shared pool. A NEW row lands
-- untagged (tag / disciplines keep their table defaults; the enrich stage owns
-- them). On CONFLICT the merge NEVER wipes existing content with NULLs and NEVER
-- overwrites the enrich stage's tag / disciplines:
--   * volatile metadata (title, description, counts, duration, avatar) refreshes
--     from the new fetch, but counts/duration/avatar COALESCE so a hidden/absent
--     new value can't blank a good stored one;
--   * source_queries UNIONs the surfacing queries (dedup, best-effort order);
--   * relevance_index keeps the best (lowest) across scrapes;
--   * transcript is kept if we already had one, else adopted from the new fetch;
--   * tag / disciplines are deliberately absent from the SET (preserved).
INSERT INTO video (
    video_id, url, title, description, thumbnail_url,
    channel_name, channel_url, channel_avatar_url,
    view_count, like_count, duration_seconds,
    source_queries, relevance_index, transcript_error, transcript
)
VALUES (
    :video_id, :url, :title, :description, :thumbnail_url,
    :channel_name, :channel_url, :channel_avatar_url,
    :view_count, :like_count, :duration_seconds,
    CAST(:source_queries AS JSONB), :relevance_index,
    :transcript_error, :transcript
)
ON CONFLICT (video_id) DO UPDATE SET
    url = EXCLUDED.url,
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    thumbnail_url = EXCLUDED.thumbnail_url,
    channel_name = EXCLUDED.channel_name,
    channel_url = EXCLUDED.channel_url,
    channel_avatar_url = CASE
        WHEN EXCLUDED.channel_avatar_url <> ''
        THEN EXCLUDED.channel_avatar_url
        ELSE video.channel_avatar_url
    END,
    view_count = COALESCE(EXCLUDED.view_count, video.view_count),
    like_count = COALESCE(EXCLUDED.like_count, video.like_count),
    duration_seconds = COALESCE(
        EXCLUDED.duration_seconds, video.duration_seconds
    ),
    source_queries = COALESCE(
        (
            SELECT jsonb_agg(DISTINCT q)
            FROM jsonb_array_elements(
                video.source_queries || EXCLUDED.source_queries
            ) AS q
        ),
        video.source_queries
    ),
    relevance_index = LEAST(video.relevance_index, EXCLUDED.relevance_index),
    transcript = COALESCE(video.transcript, EXCLUDED.transcript),
    transcript_error = CASE
        WHEN video.transcript IS NOT NULL THEN video.transcript_error
        ELSE EXCLUDED.transcript_error
    END;
