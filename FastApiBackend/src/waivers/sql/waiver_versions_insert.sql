INSERT INTO gym_waiver_versions (
    waiver_id,
    gym_id,
    version_number,
    body,
    content_hash
) VALUES (
    :waiver_id,
    :gym_id,
    :version_number,
    :body,
    :content_hash
)
RETURNING *
