-- ALL schedule versions of one class, oldest first. Mirrors
-- src/classes/sql/classes_schedules_for_class.sql -- the checkin domain owns
-- its own copy per the per-domain SQL ownership convention. weekday_slots
-- (JSONB) carries the WHEN of the shape -- day -> ordered {time,
-- instructor_id} slot list, so a class may occur several times on one day
-- (replaces the old class_time + 7 weekday bools + 7 instructor columns).
-- Occurrence resolution needs the full version history (not just the
-- current one) so a past-dated check-in / sign-up resolves against
-- whichever version owned that date; the version expander windows them by
-- effective_from.
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
