-- Resolve the caller's active gym_employees row for ONE gym at an allowed
-- role set. Identity is the caller's VERIFIED email: the row must be
-- non-archived, hold an allowed employee_type, AND be backed by a
-- CONFIRMED auth.users account. The bound email is lowercased by the caller
-- and the column is compared through lower() rather than relying on the
-- stored value already being lowercase: the API's Pydantic validators
-- normalize on write, but nothing below them does — the uniqueness index is
-- `(gym_id, lower(email))`, which PERMITS a mixed-case stored value. A row
-- written by the seed or by hand would otherwise be a split brain: visible
-- with its role in GET /gyms/ (that query already lowercases) yet 403 on
-- every gym-scoped route. Every identity query lowercases both sides.
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and
-- duplicate the employee. EXISTS cannot fan out.
SELECT ge.employee_id,
       ge.employee_type
FROM gym_employees ge
WHERE ge.gym_id = CAST(:gym_id AS UUID)
  AND lower(ge.email) = :email
  AND CAST(ge.employee_type AS TEXT) = ANY(CAST(:allowed_roles AS TEXT[]))
  AND ge.archived_at IS NULL
  AND EXISTS (
      -- Pinned to the CALLER's own account (u.id = :caller_id, the JWT sub):
      -- proves the caller's account is confirmed, not just that some confirmed
      -- account holds this email. Email equality kept as defense in depth.
      SELECT 1
      FROM auth.users u
      WHERE u.id = CAST(:caller_id AS UUID)
        AND lower(u.email) = lower(ge.email)
        AND u.email_confirmed_at IS NOT NULL
  )
LIMIT 1;
