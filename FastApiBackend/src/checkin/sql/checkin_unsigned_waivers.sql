-- Check-in waiver gate: every waiver this member must sign — the union of
-- waiver_ids across their CURRENT (active/frozen) memberships' plans — where
-- they hold NO signature at a version >= the waiver's re-sign FLOOR (the
-- highest version_number with requires_resign = true; a minor edit does not
-- re-block a prior signer). Same floor semantics as the membership-START gate
-- (memberships/sql/member_memberships_start_waivers_check.sql); the
-- requirement set matches the member-detail Waivers section
-- (waivers/sql/waiver_signatures_by_member.sql) — "the member's Waivers
-- section must be all-green to check in". Deleted waivers are excluded. A
-- sanctioned cross-domain TABLE read (checkin -> waiver/plan tables), like
-- the classes board's signup counts.
WITH required AS (
    SELECT DISTINCT CAST(elem AS UUID) AS waiver_id
    FROM member_memberships_status mms
    JOIN membership_plans mp
        ON mp.plan_id = mms.plan_id
       AND mp.gym_id = mms.gym_id
    CROSS JOIN LATERAL jsonb_array_elements_text(mp.waiver_ids) AS elem
    WHERE mms.member_id = :member_id
      AND mms.gym_id = :gym_id
      AND mms.status IN ('active', 'frozen')
),
floor AS (
    SELECT
        r.waiver_id,
        COALESCE(
            MAX(v.version_number) FILTER (WHERE v.requires_resign),
            1
        ) AS floor_vn
    FROM required r
    JOIN gym_waiver_versions v
        ON v.waiver_id = r.waiver_id
       AND v.gym_id = :gym_id
    GROUP BY r.waiver_id
)
SELECT w.waiver_id, w.name
FROM required r
JOIN gym_waivers w
    ON w.waiver_id = r.waiver_id
   AND w.gym_id = :gym_id
   AND w.is_deleted = false
JOIN floor f ON f.waiver_id = r.waiver_id
LEFT JOIN LATERAL (
    SELECT 1
    FROM member_waiver_signatures s
    JOIN gym_waiver_versions sv ON sv.version_id = s.waiver_version_id
    WHERE s.member_id = :member_id
      AND s.waiver_id = r.waiver_id
      AND sv.version_number >= f.floor_vn
    LIMIT 1
) sig ON true
WHERE sig IS NULL
