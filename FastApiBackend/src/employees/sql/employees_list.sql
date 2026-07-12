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
    (u.email_confirmed_at IS NOT NULL) AS has_verified_account
FROM gym_employees ge
LEFT JOIN auth.users u ON lower(u.email) = ge.email
WHERE ge.gym_id = CAST(:gym_id AS UUID)
  AND ge.archived_at IS NULL
ORDER BY ge.created_at ASC
