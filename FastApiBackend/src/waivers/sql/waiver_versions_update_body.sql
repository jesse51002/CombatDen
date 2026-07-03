-- Edit an UNSIGNED waiver version's body in place (same version_number).
-- Only ever called by the service when the version has 0 signatures; signed
-- versions are frozen and forked into a new version instead.
UPDATE gym_waiver_versions
SET body = :body,
    content_hash = :content_hash,
    -- NULL = leave the flag untouched
    requires_resign = COALESCE(CAST(:requires_resign AS BOOLEAN), requires_resign)
WHERE version_id = :version_id
  AND gym_id = :gym_id
RETURNING *
