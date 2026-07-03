-- Resolve a member's gym payer-auth waiver + its current version.
-- The link flow uses this to know which waiver version the payer is signing and
-- to freeze that version's content_hash onto the signature. Returns no row if
-- the member's gym has no payer-auth waiver (the gate cannot proceed).
SELECT
    w.gym_id,
    w.waiver_id,
    w.current_version_id AS version_id,
    v.content_hash
FROM members mem
JOIN gym_waivers w
    ON w.gym_id = mem.gym_id
    AND w.waiver_type = 'payer_auth'
    AND w.is_deleted = false
JOIN gym_waiver_versions v
    ON v.version_id = w.current_version_id
WHERE mem.member_id = :member_id
