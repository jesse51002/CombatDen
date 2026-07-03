SELECT
    v.version_id,
    v.waiver_id,
    v.gym_id,
    v.version_number,
    v.body,
    v.content_hash,
    v.requires_resign,
    v.created_at,
    (
        SELECT COUNT(*)
        FROM member_waiver_signatures s
        WHERE s.waiver_version_id = v.version_id
    ) AS signature_count
FROM gym_waiver_versions v
WHERE v.version_id = :version_id
