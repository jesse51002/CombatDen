-- Append a new spec version for a gym (the spec is append-only; readers take the
-- latest). The whole config is snapshotted each version. `source` records what
-- produced it (admin_update / feed_update / system_update). Returns the inserted
-- row so the caller can project it without a re-read.
INSERT INTO gym_video_spec (
    gym_id,
    gym_type,
    short_videos_desc,
    short_avoid_desc,
    videos_desc,
    avoid_desc,
    queries,
    source,
    imported_from
) VALUES (
    CAST(:gym_id AS UUID),
    CAST(:gym_type AS JSONB),
    :short_videos_desc,
    :short_avoid_desc,
    :videos_desc,
    :avoid_desc,
    CAST(:queries AS JSONB),
    CAST(:source AS gym_video_spec_source),
    :imported_from
)
RETURNING
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
