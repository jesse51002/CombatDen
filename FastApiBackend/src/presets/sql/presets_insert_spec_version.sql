-- Append a new versioned spec row for the gym (append-only; no ON CONFLICT).
-- spec_id and created_at are DB-defaulted.
INSERT INTO gym_video_spec (
    gym_id, gym_type, short_videos_desc, short_avoid_desc,
    videos_desc, avoid_desc, queries, source, imported_from
) VALUES (
    CAST(:gym_id AS UUID), CAST(:gym_type AS JSONB), :short_videos_desc, :short_avoid_desc,
    :videos_desc, :avoid_desc, CAST(:queries AS JSONB),
    CAST(:source AS gym_video_spec_source), :imported_from
)
