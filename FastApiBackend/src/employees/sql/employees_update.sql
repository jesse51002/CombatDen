UPDATE gym_employees
SET {set_clause}
WHERE employee_id = CAST(:employee_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND archived_at IS NULL
RETURNING employee_id
