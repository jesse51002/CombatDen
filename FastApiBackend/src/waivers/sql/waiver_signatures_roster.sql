-- Per-waiver signature roster: every member at the gym and whether they have
-- signed this waiver (their latest signature), which version, and when.
SELECT
    m.member_id,
    m.first_name,
    m.last_name,
    (s.signature_id IS NOT NULL) AS signed,
    s.signed_at,
    s.waiver_version_id,
    sv.version_number,
    (
        s.waiver_version_id IS NOT NULL
        AND s.waiver_version_id = w.current_version_id
    ) AS signed_current_version
FROM gym_waivers w
JOIN members m
       ON m.gym_id = w.gym_id
LEFT JOIN LATERAL (
    SELECT sig.signature_id, sig.signed_at, sig.waiver_version_id
    FROM member_waiver_signatures sig
    WHERE sig.member_id = m.member_id
      AND sig.waiver_id = w.waiver_id
    ORDER BY sig.signed_at DESC
    LIMIT 1
) s ON true
LEFT JOIN gym_waiver_versions sv
       ON sv.version_id = s.waiver_version_id
WHERE w.waiver_id = :waiver_id
  AND w.gym_id = :gym_id
  AND w.is_deleted = false
ORDER BY m.first_name, m.last_name
