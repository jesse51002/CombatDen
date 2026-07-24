-- Raw waiver version rows for the gym -- the full versioned document text
-- (body) + its content hash, so the exact wording of every version is exported.
SELECT
    wv.version_id,
    wv.waiver_id,
    wv.gym_id,
    wv.version_number,
    wv.body,
    wv.content_hash,
    wv.requires_resign,
    wv.created_at
FROM gym_waiver_versions wv
WHERE wv.gym_id = CAST(:gym_id AS UUID)
ORDER BY wv.created_at ASC, wv.version_id ASC
