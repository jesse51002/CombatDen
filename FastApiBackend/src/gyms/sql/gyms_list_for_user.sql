-- All gyms the authenticated user is an employee of, annotated with
-- their role. Identity is the caller's verified email (stored lowercase);
-- ALL roles enter the CRM, so there is no role filter here — the response
-- carries ge.employee_type. Archived employees are excluded. The partial
-- unique index unique_employee_email_gym on (gym_id, lower(email))
-- WHERE email IS NOT NULL guarantees one row per email per gym, so no
-- de-duplication is needed.
--
-- This is a ROLE-RESOLUTION query (it hands the caller their role at each
-- gym), so it carries the same verified-account predicate as every other
-- one: a CONFIRMED auth.users row must exist for the email. A scalar
-- EXISTS, never a JOIN — auth.users is unique on email only
-- WHERE is_sso_user = false, so a join could match several rows and
-- duplicate the gym. EXISTS cannot fan out.
SELECT g.gym_id,
       g.gym_name,
       g.gym_description,
       g.timezone,
       g.sub_rank_type,
       g.logo_url,
       g.theme_design_id,
       ge.employee_type,
       ge.theme_preference
FROM gyms g
JOIN gym_employees ge ON ge.gym_id = g.gym_id
WHERE lower(ge.email) = :email
  AND ge.archived_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM auth.users u
      WHERE lower(u.email) = lower(ge.email)
        AND u.email_confirmed_at IS NOT NULL
  )
ORDER BY ge.created_at ASC;
