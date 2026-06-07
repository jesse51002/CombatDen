-- Delete the bootstrap owner employee row for a failed gym create.
-- Scoped to employee_type='owner' so it cannot accidentally remove
-- trainers or admins.
DELETE FROM gym_employees
WHERE gym_id        = :gym_id
  AND employee_type = 'owner';
