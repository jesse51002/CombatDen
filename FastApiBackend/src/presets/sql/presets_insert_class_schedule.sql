-- Mint the ONE initial schedule version (gym_class_schedules) for a
-- preset-imported class. effective_from is backdated well before the
-- earliest seeded attendance date (see PresetsService._SCHEDULE_EFFECTIVE_FROM_
-- BACKDATE_DAYS) -- purely for a sensible-looking row, since the FIRST
-- version of a class owns occurrences back to negative infinity regardless
-- (ClassesVersionExpander). timezone freezes the gym's current zone. Preset
-- classes are always weekly Mon-Fri with one instructor across every weekday
-- and no end date (mirrors the always-weekly shape ClassesExpander expects).
-- The enum is cast functionally (never :p::type -- see CLAUDE.md).
INSERT INTO gym_class_schedules (
    class_id, gym_id, effective_from, timezone,
    class_time, duration_minutes, recurring_unit, recurring_interval,
    mon, tue, wed, thu, fri, sat, sun,
    mon_instructor_id, tue_instructor_id, wed_instructor_id,
    thu_instructor_id, fri_instructor_id,
    start_date
) VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:effective_from AS TIMESTAMPTZ),
    :timezone,
    CAST(:class_time AS TIME),
    :duration_minutes,
    CAST('weekly' AS recurring_unit),
    1,
    TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
    CAST(:instructor_id AS UUID),
    CAST(:instructor_id AS UUID),
    CAST(:instructor_id AS UUID),
    CAST(:instructor_id AS UUID),
    CAST(:instructor_id AS UUID),
    CAST(:start_date AS DATE)
)
RETURNING schedule_id
