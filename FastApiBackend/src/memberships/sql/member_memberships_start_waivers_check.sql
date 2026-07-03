-- Membership-start waiver gate: given the request's (member_id, plan_id) pairs,
-- return every required waiver the member has NOT signed at a current-enough
-- version. Applies to ALL plan types (the caller passes every item's pair).
--
-- For each pair, the plan's waiver_ids are the required waivers. A member is
-- compliant for a waiver iff they have a signature on a version whose
-- version_number >= the waiver's re-sign FLOOR = the highest version_number
-- among that waiver's versions with requires_resign = true (so a minor edit,
-- requires_resign = false, does NOT re-block a prior signer). Deleted waivers are
-- excluded (they cannot be signed through the current path).
--
-- Bind-cast rule: the :pairs param is cast with CAST(... AS JSONB), never the
-- shorthand colon-colon cast (asyncpg cannot bind a param before that operator).
WITH pairs AS (
    SELECT p.member_id, p.plan_id
    FROM jsonb_to_recordset(CAST(:pairs AS JSONB))
        AS p(member_id UUID, plan_id UUID)
),
required AS (
    SELECT pr.member_id, CAST(elem AS UUID) AS waiver_id
    FROM pairs pr
    JOIN membership_plans mp
        ON mp.plan_id = pr.plan_id
       AND mp.gym_id = :gym_id
    CROSS JOIN LATERAL jsonb_array_elements_text(mp.waiver_ids) AS elem
),
floor AS (
    SELECT
        r.waiver_id,
        COALESCE(
            MAX(v.version_number) FILTER (WHERE v.requires_resign),
            1
        ) AS floor_vn
    FROM (SELECT DISTINCT waiver_id FROM required) r
    JOIN gym_waiver_versions v
        ON v.waiver_id = r.waiver_id
       AND v.gym_id = :gym_id
    GROUP BY r.waiver_id
)
SELECT DISTINCT r.member_id, r.waiver_id, w.name
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
    WHERE s.member_id = r.member_id
      AND s.waiver_id = r.waiver_id
      AND sv.version_number >= f.floor_vn
    LIMIT 1
) sig ON true
WHERE sig IS NULL
