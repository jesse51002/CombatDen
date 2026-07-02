-- The class's CURRENT schedule version — a one-row read against the
-- gym_class_schedules_current view (the latest version per class), used by
-- the mint engine's deep-equal check and outgoing-version lookup so a
-- schedule edit never scans the class's whole append-only history.
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
FROM gym_class_schedules_current
WHERE class_id = CAST(:class_id AS UUID)
