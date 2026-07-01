-- Mint one append-only schedule VERSION (gym_class_schedules). effective_from
-- is the server-stamped mint instant (never future, never edited); timezone is
-- the gym's zone frozen at mint. The recurring_unit enum is cast functionally
-- (never :p::type — see CLAUDE.md).
INSERT INTO gym_class_schedules (
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
)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    :effective_from,
    :timezone,
    :class_time,
    :duration_minutes,
    CAST(:recurring_unit AS recurring_unit),
    :recurring_interval,
    :sun, :mon, :tue, :wed, :thu, :fri, :sat,
    :sun_instructor_id,
    :mon_instructor_id,
    :tue_instructor_id,
    :wed_instructor_id,
    :thu_instructor_id,
    :fri_instructor_id,
    :sat_instructor_id,
    :start_date,
    :end_date
)
RETURNING schedule_id
