-- Gym staff + instructor roster (gym_employees): name, role, contact, and
-- dates. The auth linkage (user_id) and the CRM theme preference are omitted --
-- they are not part of the gym's operational data export.
SELECT
    e.employee_id,
    e.gym_id,
    e.employee_type,
    e.first_name,
    e.last_name,
    e.phone,
    e.email,
    e.employee_pic_url,
    e.employee_public_description,
    e.created_at
FROM gym_employees e
WHERE e.gym_id = CAST(:gym_id AS UUID)
ORDER BY e.created_at ASC, e.employee_id ASC
