-- Resolve the caller's active gym_employees row for ONE gym at an allowed
-- role set. Identity is the caller's VERIFIED email: the row must be
-- non-archived, hold an allowed employee_type, AND be backed by a
-- CONFIRMED auth.users account. Stored employee emails are lowercase and
-- the bound email is lowercased before the query, so this is an exact match.
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and
-- duplicate the employee. EXISTS cannot fan out.
SELECT ge.employee_id,
       ge.employee_type
FROM gym_employees ge
WHERE ge.gym_id = CAST(:gym_id AS UUID)
  AND ge.email = :email
  AND CAST(ge.employee_type AS TEXT) = ANY(CAST(:allowed_roles AS TEXT[]))
  AND ge.archived_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE lower(u.email) = ge.email
        AND u.email_confirmed_at IS NOT NULL
  )
LIMIT 1;
