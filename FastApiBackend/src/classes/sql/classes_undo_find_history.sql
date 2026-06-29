-- Find the materialized class_history row for a gym-local calendar day.
-- The caller passes the day's UTC bounds [start, end) (gym-local midnight to
-- the next midnight, converted to UTC), so this matches the occurrence
-- regardless of any per-occurrence time override (a rescheduled / retimed
-- occurrence still falls inside the same local day). Returns nothing when the
-- occurrence was never materialized (no check-ins yet).
SELECT class_history_id
FROM class_history
WHERE class_id = CAST(:class_id AS UUID)
  AND occurred_at >= CAST(:start AS TIMESTAMPTZ)
  AND occurred_at <  CAST(:end AS TIMESTAMPTZ)
ORDER BY occurred_at
