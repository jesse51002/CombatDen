-- Per-member waiver status for the member-detail Waivers section: only the
-- waivers this member must sign for the memberships they currently hold
-- (the union of waiver_ids across their non-terminal — active/frozen —
-- memberships' plans), plus this member's latest signature status for each.
WITH required_waivers AS (
    SELECT DISTINCT CAST(elem AS uuid) AS waiver_id
    FROM member_memberships_status mms
    JOIN membership_plans mp
        ON mp.plan_id = mms.plan_id
        AND mp.gym_id = mms.gym_id
    CROSS JOIN LATERAL
        jsonb_array_elements_text(mp.waiver_ids) AS elem
    WHERE mms.member_id = :member_id
      AND mms.gym_id = :gym_id
      AND mms.status IN ('active', 'frozen')
)
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
  AND w.waiver_id IN (SELECT waiver_id FROM required_waivers)
ORDER BY w.created_at DESC
