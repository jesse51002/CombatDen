UPDATE gym_employees
SET archived_at = now()
WHERE employee_id = CAST(:employee_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND archived_at IS NULL
  AND employee_type <> 'owner'
RETURNING employee_id
