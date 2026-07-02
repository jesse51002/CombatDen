-- The subset of the given instructor ids that ARE employees of the gym.
-- weekday_slots instructor_ids live inside JSONB, so the old per-column
-- composite FKs to gym_employees can't apply -- the mint path validates
-- instead: any id NOT returned here is rejected before the version INSERT.
SELECT employee_id
FROM gym_employees
WHERE gym_id = CAST(:gym_id AS UUID)
  AND employee_id = ANY(CAST(:employee_ids AS UUID[]))
