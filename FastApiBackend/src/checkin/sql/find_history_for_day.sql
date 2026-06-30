-- Find the materialized class_history row for a (class, gym) on a gym-local
-- calendar day. The caller passes the day's UTC bounds [day_start, day_end)
-- (gym-local midnight to the next midnight, converted to UTC), so the row is
-- matched regardless of any per-occurrence time override. gym_id scopes the
-- lookup to the employee's gym. Returns nothing when the occurrence was never
-- materialized (no check-ins yet).
SELECT class_history_id
FROM class_history
WHERE class_id = CAST(:class_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND occurred_at >= CAST(:day_start AS TIMESTAMPTZ)
  AND occurred_at <  CAST(:day_end AS TIMESTAMPTZ)
ORDER BY occurred_at
LIMIT 1
