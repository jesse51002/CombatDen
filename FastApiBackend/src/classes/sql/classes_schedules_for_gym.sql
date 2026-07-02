-- ALL schedule versions of every class of a gym (deleted classes included —
-- their past occurrences render forever), oldest first per class. The board
-- read groups these by class_id and hands each class's full version history
-- to the version expander.
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
WHERE gym_id = CAST(:gym_id AS UUID)
ORDER BY class_id, effective_from ASC
