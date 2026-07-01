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
    class_time,
    duration_minutes,
    recurring_unit,
    recurring_interval,
    sun, mon, tue, wed, thu, fri, sat,
    sun_instructor_id,
    mon_instructor_id,
    tue_instructor_id,
    wed_instructor_id,
    thu_instructor_id,
    fri_instructor_id,
    sat_instructor_id,
    start_date,
    end_date
FROM gym_class_schedules
WHERE class_id = CAST(:class_id AS UUID)
ORDER BY effective_from ASC
