INSERT INTO gym_waiver_versions (
    waiver_id,
    gym_id,
    version_number,
    body,
    content_hash,
    requires_resign
) VALUES (
    :waiver_id,
    :gym_id,
    :version_number,
    :body,
    :content_hash,
    :requires_resign
)
RETURNING *
