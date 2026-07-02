-- Resolve a waiver's current version + everything needed to render and
-- version-lock a new signature: whether the waiver is archived, its
-- current_version_id (the only version a new signature may target), that
-- version's template body (rendered with {{placeholders}}), the gym name, and the
-- signing member's account name — the auto-filled placeholder values. LEFT JOIN
-- the version + member so a waiver with no current version (→ 404) or a member
-- not in the gym (→ the insert FK 404s) still returns a row; JOIN gyms (always
-- present) for the gym name.
SELECT
    w.is_deleted,
    w.current_version_id,
    v.body AS template_body,
    g.name AS gym_name,
    m.first_name AS member_first_name,
    m.last_name AS member_last_name
FROM gym_waivers w
JOIN gyms g ON g.gym_id = w.gym_id
LEFT JOIN gym_waiver_versions v
    ON v.version_id = w.current_version_id
LEFT JOIN members m
    ON m.member_id = :member_id
   AND m.gym_id = w.gym_id
WHERE w.waiver_id = :waiver_id
  AND w.gym_id = :gym_id
