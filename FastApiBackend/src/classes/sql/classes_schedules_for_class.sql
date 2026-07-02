-- ALL schedule versions of one class, oldest first. The version expander
-- windows them by effective_from (a version's coverage ends where the next
-- one begins), so every caller that renders or validates occurrences loads
-- the full history — never just the current row.
SELECT
    schedule_id,
    class_id,
    gym_id,
    effective_from,
    timezone,
    duration_minutes,
    recurring_unit,
    recurring_interval,
    weekday_slots,
    start_date,
    end_date
FROM gym_class_schedules
WHERE class_id = CAST(:class_id AS UUID)
ORDER BY effective_from ASC
