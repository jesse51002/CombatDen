-- The recurring-schedule shape of a class, as APPEND-ONLY VERSIONED rows
-- (identity + immutable versions, mirroring membership_plans ->
-- membership_plan_prices and gym_discounts -> gym_discount_values).
-- gym_classes holds the identity (name, description, capacity, points...);
-- every schedule-shaped fact (time, duration, recurrence, weekday slots,
-- instructors, recurrence range) lives here.
--
-- Versioning model:
--   * A version's coverage window is [effective_from, next version's
--     effective_from) — the end is DERIVED from the next row, never stored.
--     Rows are write-once: no effective_until, no is_active, no created_at
--     (created_at would always equal effective_from — mint = effective now).
--   * effective_from is server-stamped now() at mint. It is NEVER in the
--     future (no scheduled takeovers) and never edited, so the max-
--     effective_from version always owns [its effective_from, infinity).
--   * An occurrence belongs to the version whose window contains its
--     ORIGINAL instant (original_date + the slot's time in the version's own
--     timezone). Past versions never change, so the past always re-renders
--     identically.
--   * timezone is an IANA zone FROZEN at mint (copied from gyms.timezone):
--     a version's expansion always uses its own zone, so a later gym
--     timezone change can never move any existing version's occurrences.
--     A gym timezone update mints a same-shape version (new tz) per live
--     class instead.
--
-- weekday_slots (JSONB) is the WHEN of the shape — a class may occur several
-- times on the same day, each slot with its own optional instructor:
--   * weekly:        {"mon": [{"time": "06:00", "instructor_id": "<uuid>"},
--                             {"time": "18:30", "instructor_id": null}],
--                     "sat": [{"time": "09:00", "instructor_id": null}]}
--     — only sun..sat keys; a day occurs iff its key is present with a
--     non-empty list.
--   * daily/monthly: {"all": [{"time": "07:00", "instructor_id": null}]}
--     — exactly the reserved "all" key; every candidate date gets its slots.
-- Times are 24h "HH:MM", unique per day, stored sorted ascending. Deep shape
-- validation (keys-per-unit, time format, dupes, ordering) lives in ONE
-- shared Pydantic canonicalizer (FastApiBackend classes_expander_schema.py)
-- used by both API input and DB-row parsing; SQL only guards the coarse
-- structure. instructor_id references gym_employees but CANNOT be FK-enforced
-- inside JSONB — the mint path validates instructors against the gym's
-- employees before writing.
CREATE TYPE recurring_unit AS ENUM ('daily', 'weekly', 'monthly');

CREATE TABLE gym_class_schedules (
    schedule_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_class_schedule_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_class_schedule_gym REFERENCES gyms(gym_id),

    -- When this version starts owning occurrences (server now() at mint).
    effective_from TIMESTAMPTZ NOT NULL,
    -- IANA timezone frozen at mint; validated by the AT TIME ZONE probe.
    timezone TEXT NOT NULL
        CONSTRAINT chk_class_schedule_timezone_valid
        CHECK ((now() AT TIME ZONE timezone) IS NOT NULL),

    -- The schedule shape.
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    recurring_unit recurring_unit NOT NULL,
    recurring_interval INTEGER NOT NULL DEFAULT 1 CHECK (recurring_interval > 0),
    -- WHEN the class occurs: day -> ordered slot list (see header). Coarse
    -- structure only here; the shared Pydantic canonicalizer owns the deep
    -- validation.
    weekday_slots JSONB NOT NULL
        CONSTRAINT chk_class_schedule_slots_shape
        CHECK (jsonb_typeof(weekday_slots) = 'object'
               AND weekday_slots <> '{}'::jsonb),
    -- The recurrence range (which dates the class runs on) — part of the
    -- shape, NOT the version boundary (that's effective_from, a timestamptz,
    -- so several edits can land on one day).
    start_date DATE NOT NULL,
    end_date DATE,

    PRIMARY KEY (schedule_id),
    CONSTRAINT uq_class_schedule_version UNIQUE (class_id, effective_from),
    CHECK (end_date IS NULL OR end_date >= start_date),

    CONSTRAINT fk_class_schedule_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id)
);

CREATE INDEX idx_gym_class_schedules_class_from
    ON gym_class_schedules (class_id, effective_from DESC);

-- The current (present/future-owning) version per class. Read paths that only
-- need "the schedule as it stands now" (class CRUD reads, the check-in
-- resolver's fast path) use this view; window/board reads that span history
-- load all versions and window them in the expander.
CREATE VIEW gym_class_schedules_current
WITH (security_invoker = true) AS
SELECT DISTINCT ON (class_id) *
FROM gym_class_schedules
ORDER BY class_id, effective_from DESC, schedule_id DESC;
