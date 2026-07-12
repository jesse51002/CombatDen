-- All gyms the authenticated user is an employee of, annotated with
-- their role. Identity is the caller's verified email (stored lowercase);
-- ALL roles enter the CRM, so there is no role filter here — the response
-- carries ge.employee_type. Archived employees are excluded. UNIQUE
-- (email, gym_id) guarantees one row per gym, so no de-duplication is
-- needed.
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
ORDER BY ge.created_at ASC;
