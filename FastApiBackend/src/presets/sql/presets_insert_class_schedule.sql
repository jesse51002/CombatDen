-- Mint the ONE initial schedule version (gym_class_schedules) for a
-- preset-imported class. effective_from is backdated well before the
-- earliest seeded attendance date (see PresetsService._SCHEDULE_EFFECTIVE_FROM_
-- BACKDATE_DAYS) -- purely for a sensible-looking row, since the FIRST
-- version of a class owns occurrences back to negative infinity regardless
-- (ClassesVersionExpander). timezone freezes the gym's current zone. Preset
-- classes are always weekly Mon-Fri, one slot per weekday (the FIRST
-- imported class of the import additionally gets a second same-day slot --
-- see PresetsService._build_weekday_slots) and no end date. weekday_slots
-- arrives as a JSON string and is cast functionally (never :p::jsonb -- see
-- CLAUDE.md), mirroring classes_schedule_insert.sql.
INSERT INTO gym_class_schedules (
    class_id, gym_id, effective_from, timezone,
    duration_minutes, recurring_unit, recurring_interval,
    weekday_slots, start_date
) VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:effective_from AS TIMESTAMPTZ),
    :timezone,
    :duration_minutes,
    CAST('weekly' AS recurring_unit),
    1,
    CAST(:weekday_slots AS JSONB),
    CAST(:start_date AS DATE)
)
RETURNING schedule_id
