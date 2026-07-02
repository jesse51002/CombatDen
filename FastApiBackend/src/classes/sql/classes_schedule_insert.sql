-- Mint one append-only schedule VERSION (gym_class_schedules). effective_from
-- is the server-stamped mint instant (never future, never edited); timezone is
-- the gym's zone frozen at mint. weekday_slots arrives as a JSON string and is
-- cast functionally (never :p::type — see CLAUDE.md), like the enum.
INSERT INTO gym_class_schedules (
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
)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    :effective_from,
    :timezone,
    :duration_minutes,
    CAST(:recurring_unit AS recurring_unit),
    :recurring_interval,
    CAST(:weekday_slots AS JSONB),
    :start_date,
    :end_date
)
RETURNING schedule_id
