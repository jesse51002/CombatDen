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
--     ORIGINAL instant (original_date + class_time in the version's own
--     timezone). Past versions never change, so the past always re-renders
--     identically.
--   * timezone is an IANA zone FROZEN at mint (copied from gyms.timezone):
--     a version's expansion always uses its own zone, so a later gym
--     timezone change can never move any existing version's occurrences.
--     A gym timezone update mints a same-shape version (new tz) per live
--     class instead.
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
    class_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    recurring_unit recurring_unit NOT NULL,
    recurring_interval INTEGER NOT NULL DEFAULT 1 CHECK (recurring_interval > 0),
    sun BOOLEAN NOT NULL DEFAULT FALSE,
    mon BOOLEAN NOT NULL DEFAULT FALSE,
    tue BOOLEAN NOT NULL DEFAULT FALSE,
    wed BOOLEAN NOT NULL DEFAULT FALSE,
    thu BOOLEAN NOT NULL DEFAULT FALSE,
    fri BOOLEAN NOT NULL DEFAULT FALSE,
    sat BOOLEAN NOT NULL DEFAULT FALSE,
    sun_instructor_id UUID,
    mon_instructor_id UUID,
    tue_instructor_id UUID,
    wed_instructor_id UUID,
    thu_instructor_id UUID,
    fri_instructor_id UUID,
    sat_instructor_id UUID,
    -- The recurrence range (which dates the class runs on) — part of the
    -- shape, NOT the version boundary (that's effective_from, a timestamptz,
    -- so several edits can land on one day).
    start_date DATE NOT NULL,
    end_date DATE,

    PRIMARY KEY (schedule_id),
    CONSTRAINT uq_class_schedule_version UNIQUE (class_id, effective_from),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CHECK (recurring_unit != 'weekly' OR sun OR mon OR tue OR wed OR thu OR fri OR sat),

    CONSTRAINT fk_class_schedule_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_schedule_sun_instructor
        FOREIGN KEY (sun_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_mon_instructor
        FOREIGN KEY (mon_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_tue_instructor
        FOREIGN KEY (tue_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_wed_instructor
        FOREIGN KEY (wed_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_thu_instructor
        FOREIGN KEY (thu_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_fri_instructor
        FOREIGN KEY (fri_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id),
    CONSTRAINT fk_class_schedule_sat_instructor
        FOREIGN KEY (sat_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
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
