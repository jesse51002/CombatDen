-- Per-member waiver status: every non-deleted gym waiver and this member's
-- latest signature status for it (for the member-detail Waivers section).
SELECT
    w.waiver_id,
    w.name,
    w.current_version_id,
    cv.version_number AS current_version_number,
    (s.signature_id IS NOT NULL) AS signed,
    s.waiver_version_id AS signed_version_id,
    sv.version_number AS signed_version_number,
    s.signed_at,
    (
        s.waiver_version_id IS NOT NULL
        AND s.waiver_version_id = w.current_version_id
    ) AS signed_current_version
FROM gym_waivers w
LEFT JOIN gym_waiver_versions cv
       ON cv.version_id = w.current_version_id
LEFT JOIN LATERAL (
    SELECT sig.signature_id, sig.signed_at, sig.waiver_version_id
    FROM member_waiver_signatures sig
    WHERE sig.waiver_id = w.waiver_id
      AND sig.member_id = :member_id
    ORDER BY sig.signed_at DESC
    LIMIT 1
) s ON true
LEFT JOIN gym_waiver_versions sv
       ON sv.version_id = s.waiver_version_id
WHERE w.gym_id = :gym_id
  AND w.is_deleted = false
ORDER BY w.created_at DESC
