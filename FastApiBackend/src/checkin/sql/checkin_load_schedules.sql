-- ALL schedule versions of one class, oldest first. Mirrors
-- src/classes/sql/classes_schedules_for_class.sql -- the checkin domain owns
-- its own copy per the per-domain SQL ownership convention (gym_classes no
-- longer embeds the recurrence shape). Occurrence resolution needs the full
-- version history (not just the current one) so a past-dated check-in /
-- sign-up resolves against whichever version owned that date; the version
-- expander windows them by effective_from.
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
