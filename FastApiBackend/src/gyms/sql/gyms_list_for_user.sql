-- All gyms the authenticated user may administer, annotated with
-- their role. Owners and admins can view/manage a gym in the admin
-- app; trainers are excluded. UNIQUE (user_id, gym_id) guarantees
-- one row per gym, so no de-duplication is needed.
SELECT g.gym_id,
       g.created_at,
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
WHERE ge.user_id = :user_id
  AND ge.employee_type IN ('owner', 'admin')
ORDER BY ge.created_at ASC;
