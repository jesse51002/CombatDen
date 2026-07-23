-- Gym staff + instructor roster (gym_employees): name, role, contact, dates,
-- and the soft-archive flag. Identity is the (verified) email itself -- there
-- is no separate auth-account id column. Archived (revoked) rows ARE included
-- -- this is a raw completeness export. Omitted: the employee's CRM admin-app
-- theme preference (theme_preference) is a personal UI setting, not the gym's
-- operational data; invite_status is derived at read time (from auth.users),
-- never stored, so it is not a column to export.
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
    e.archived_at,
    e.created_at
FROM gym_employees e
WHERE e.gym_id = CAST(:gym_id AS UUID)
ORDER BY e.created_at ASC, e.employee_id ASC
