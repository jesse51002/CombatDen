-- Raw schedule VERSIONS for the gym's classes -- ALL append-only versions, no
-- "current version" collapse (the full immutable schedule history). weekday_slots
-- is a JSONB object rendered as its text form. Ordered by class then by the
-- version's effective_from (its coverage-window start).
SELECT
    sch.schedule_id,
    sch.class_id,
    sch.gym_id,
    sch.effective_from,
    sch.timezone,
    sch.duration_minutes,
    sch.recurring_unit,
    sch.recurring_interval,
    CAST(sch.weekday_slots AS TEXT) AS weekday_slots,
    sch.start_date,
    sch.end_date
FROM gym_class_schedules sch
WHERE sch.gym_id = CAST(:gym_id AS UUID)
ORDER BY sch.class_id ASC, sch.effective_from ASC, sch.schedule_id ASC
