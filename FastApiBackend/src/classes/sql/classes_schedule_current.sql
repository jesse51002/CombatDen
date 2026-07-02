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
    duration_minutes,
    recurring_unit,
    recurring_interval,
    weekday_slots,
    start_date,
    end_date
FROM gym_class_schedules_current
WHERE class_id = CAST(:class_id AS UUID)
