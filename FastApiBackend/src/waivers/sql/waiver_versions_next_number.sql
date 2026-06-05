SELECT COALESCE(MAX(version_number), 0) + 1 AS next_version_number
FROM gym_waiver_versions
WHERE waiver_id = :waiver_id
