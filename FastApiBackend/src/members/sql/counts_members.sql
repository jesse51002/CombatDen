SELECT
    COUNT(*) AS all_count,
    COUNT(*) FILTER (WHERE status = 'trial') AS trial_count,
    COUNT(*) FILTER (WHERE status = 'active') AS active_count,
    COUNT(*) FILTER (WHERE status = 'inactive') AS inactive_count
FROM members_with_status
WHERE gym_id = :gym_id
