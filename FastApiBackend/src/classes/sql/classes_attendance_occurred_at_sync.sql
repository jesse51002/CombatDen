-- Re-sync the denormalized EFFECTIVE start instant on a kept occurrence's
-- attendance rows (identity key unchanged) -- scoped to the exact
-- (original_date, original_time) slot, so a same-day sibling occurrence's
-- rows are never touched. The two callers are the paths that re-time an
-- occurrence WITHOUT wiping it: a same-slot override on an attended
-- occurrence, and a reschedule to today/past (keep-and-redate). occurred_at
-- is only consumed by time-window SQL (streak / cycle counts / last_class);
-- identity joins always use (class_id, original_date, original_time). A
-- no-op when the occurrence has no attendance.
UPDATE member_attendance
SET occurred_at = :occurred_at
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
  AND original_time = CAST(:original_time AS TIME)
