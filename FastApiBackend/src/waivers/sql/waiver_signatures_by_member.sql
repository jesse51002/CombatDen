-- Per-member waiver status for the member-detail Waivers section: the UNION
-- of (a) the waivers this member must sign for the memberships they
-- currently hold (waiver_ids across their non-terminal — active/frozen —
-- memberships' plans) and (b) every waiver they have EVER signed — so a
-- signature stays visible after the waiver stops being required (or is
-- archived; the signature is the legal record).
--
-- Per row: `required` (in the current required set), the member's latest
-- signature, and `meets_floor` — whether that signature is at a version >=
-- the waiver's re-sign FLOOR (highest version_number with requires_resign =
-- true; the same compliance rule as the purchase + check-in gates). Signed
-- below the floor = the CRM's yellow "needs re-sign" state.
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
),
signed_waivers AS (
    SELECT DISTINCT sig.waiver_id
    FROM member_waiver_signatures sig
    WHERE sig.member_id = :member_id
      AND sig.gym_id = :gym_id
),
relevant AS (
    SELECT waiver_id FROM required_waivers
    UNION
    SELECT waiver_id FROM signed_waivers
),
floors AS (
    SELECT
        r.waiver_id,
        COALESCE(
            MAX(v.version_number) FILTER (WHERE v.requires_resign),
            1
        ) AS floor_vn
    FROM relevant r
    JOIN gym_waiver_versions v
        ON v.waiver_id = r.waiver_id
       AND v.gym_id = :gym_id
    GROUP BY r.waiver_id
)
SELECT
    w.waiver_id,
    w.name,
    w.waiver_type,
    w.is_deleted,
    (w.waiver_id IN (SELECT waiver_id FROM required_waivers)) AS required,
    w.current_version_id,
    cv.version_number AS current_version_number,
    (s.signature_id IS NOT NULL) AS signed,
    s.waiver_version_id AS signed_version_id,
    sv.version_number AS signed_version_number,
    s.signed_at,
    (
        s.waiver_version_id IS NOT NULL
        AND s.waiver_version_id = w.current_version_id
    ) AS signed_current_version,
    (
        sv.version_number IS NOT NULL
        AND sv.version_number >= f.floor_vn
    ) AS meets_floor
FROM gym_waivers w
JOIN floors f ON f.waiver_id = w.waiver_id
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
  AND w.waiver_id IN (SELECT waiver_id FROM relevant)
ORDER BY w.created_at DESC
