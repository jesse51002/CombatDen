-- Resolve a staff email + the gym branding for the template. Archived
-- employees are skipped: a revoked employee must never receive gym mail.
-- gym_employees.email is nullable (a trainer row may be instructor DATA
-- with no login), so a NULL address simply yields no row here.
SELECT
    lower(ge.email) AS email,
    ge.first_name AS first_name,
    g.gym_name AS gym_name,
    g.logo_url AS logo_url
FROM gym_employees ge
JOIN gyms g ON g.gym_id = ge.gym_id
WHERE ge.employee_id = CAST(:subject_id AS UUID)
  AND ge.gym_id = CAST(:gym_id AS UUID)
  AND ge.archived_at IS NULL
  AND ge.email IS NOT NULL
