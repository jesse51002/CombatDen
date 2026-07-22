SELECT
    ge.employee_id,
    ge.gym_id,
    ge.employee_type,
    ge.first_name,
    ge.last_name,
    ge.phone,
    ge.email,
    ge.employee_pic_url,
    ge.employee_public_description,
    ge.created_at,
    -- A scalar EXISTS, never a LEFT JOIN: auth.users is unique on email only
    -- WHERE is_sso_user = false, so a join could match several rows and
    -- duplicate the employee in the roster. EXISTS cannot fan out.
    EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE lower(u.email) = lower(ge.email)
          AND u.email_confirmed_at IS NOT NULL
    ) AS has_verified_account
FROM gym_employees ge
WHERE ge.gym_id = CAST(:gym_id AS UUID)
  AND ge.archived_at IS NULL
ORDER BY ge.created_at ASC
