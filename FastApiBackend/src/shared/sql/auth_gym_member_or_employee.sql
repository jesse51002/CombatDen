-- Authorize a caller to READ a gym's branding/showcase: a GYM-LEVEL read that
-- ANY of the gym's four employee roles OR ANY of its members may make. The
-- caller's VERIFIED email must match EITHER a non-archived gym_employees row at
-- :gym_id (any employee_type) OR any members row at :gym_id (NO
-- membership-status filter — an engagement-only member with no active
-- membership still sees their gym's theme), AND back a CONFIRMED auth.users
-- account that is the caller's OWN.
--
-- The bound email is lowercased by the caller; both columns are compared
-- through lower() (a hand-written / seed row MAY carry a mixed-case value — the
-- employee uniqueness index is on lower(email), which permits it).
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and fan out.
-- EXISTS cannot fan out. The confirmed-account EXISTS is pinned to the CALLER's
-- OWN account (u.id = :caller_id, the JWT sub): the caller's own account must be
-- confirmed, not merely that some account holds this email. Email equality kept
-- as defense in depth.
SELECT
    (
        EXISTS (
            SELECT 1
            FROM gym_employees ge
            WHERE ge.gym_id = CAST(:gym_id AS UUID)
              AND lower(ge.email) = :email
              AND ge.archived_at IS NULL
        )
        OR EXISTS (
            SELECT 1
            FROM members m
            WHERE m.gym_id = CAST(:gym_id AS UUID)
              AND lower(m.email) = :email
        )
    )
    AND EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE u.id = CAST(:caller_id AS UUID)
          AND lower(u.email) = :email
          AND u.email_confirmed_at IS NOT NULL
    ) AS authorized;
