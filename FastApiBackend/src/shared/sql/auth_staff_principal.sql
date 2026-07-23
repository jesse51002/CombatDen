-- The gym-AGNOSTIC staff-principal check: does the caller hold one of the
-- allowed roles on a non-archived gym_employees row at ANY gym, backed by a
-- CONFIRMED auth.users account? Used by endpoints that take no gym_id
-- (e.g. the shared image-upload proxy).
--
-- A scalar EXISTS, never a JOIN: auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and
-- duplicate the employee. EXISTS cannot fan out.
SELECT ge.employee_id
FROM gym_employees ge
WHERE lower(ge.email) = :email
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
