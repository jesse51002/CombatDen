SELECT
    w.waiver_id,
    w.gym_id,
    w.name,
    w.current_version_id,
    w.is_deleted,
    w.created_at,
    w.updated_at,
    cv.version_number AS current_version_number,
    (
        SELECT COUNT(*)
        FROM member_waiver_signatures s
        WHERE s.waiver_version_id = w.current_version_id
    ) AS current_version_signed_count
FROM gym_waivers w
LEFT JOIN gym_waiver_versions cv
       ON cv.version_id = w.current_version_id
WHERE w.waiver_id = :waiver_id
  AND w.gym_id = :gym_id
  AND w.is_deleted = false
