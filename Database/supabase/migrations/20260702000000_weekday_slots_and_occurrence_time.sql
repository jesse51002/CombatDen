-- Hand-authored migration.
-- Two independent changes reaching the schemas/ end state:
--
--   1. gym_class_schedules: class_time + the 7 weekday booleans (sun..sat) +
--      the 7 per-day {day}_instructor_id columns collapse into ONE
--      weekday_slots JSONB column (day -> ordered slot list, each slot an
--      optional time + instructor_id -- see schemas/gym_class_schedules.sql
--      header for the exact shape). The gym_class_schedules_current view
--      (SELECT DISTINCT ON (class_id) *) is dropped before the column
--      surgery (it pins the old column list) and recreated afterwards with
--      security_invoker preserved (losing it would bypass gym_class_schedules'
--      RLS -- a tenant leak).
--
--   2. The occurrence key on member_attendance / class_signups /
--      class_instance_exceptions widens from (class_id, original_date) to
--      (class_id, original_date, original_time), because weekday_slots lets a
--      class occur several times on the same gym-local date -- date alone no
--      longer disambiguates an occurrence.
--
-- DATA POLICY -- destructive, dev-only rebuild: this is demo data, so rows in
-- the five reshaped/re-keyed tables are deleted up front (member_attendance,
-- class_signups, class_instance_exceptions, class_range_exceptions,
-- gym_class_schedules) rather than backfilled. gym_classes rows are left
-- alone -- no column on gym_classes changes shape. Because the tables are
-- emptied first, every NOT NULL column added below needs no default/backfill.
--
-- Order: deletes (FK-safe) -> drop gym_class_schedules_current view -> drop
-- gym_class_schedules' old schedule-shape columns (auto-drops the 7
-- instructor FKs and the unnamed weekly >=1-day CHECK, since both involve
-- the dropped columns -- see comment at the DROP COLUMN below) -> add
-- weekday_slots -> recreate the view (+ grants) -> widen the three
-- occurrence-key constraints/indexes.

-- ============================================================
-- 0. Deletes, FK-safe order (dev/demo data; reseed after this runs)
-- ============================================================

DELETE FROM member_attendance;
DELETE FROM class_signups;
DELETE FROM class_instance_exceptions;
DELETE FROM class_range_exceptions;
DELETE FROM gym_class_schedules;

-- ============================================================
-- 1. gym_class_schedules: class_time + weekday bools + per-day instructor
--    columns -> ONE weekday_slots JSONB column
-- ============================================================

-- gym_class_schedules_current is SELECT DISTINCT ON (class_id) * -- the "*"
-- is expanded to the explicit column list at CREATE VIEW time, so it pins a
-- dependency on every column below. Drop it first; recreated with
-- security_invoker at the end of this section.
DROP VIEW gym_class_schedules_current;

-- Dropping these columns automatically drops every constraint/index that
-- involves them -- no CASCADE and no explicit DROP CONSTRAINT needed:
--   * the 7 composite instructor FKs (fk_class_schedule_{day}_instructor)
--     each involve their {day}_instructor_id column
--   * the unnamed weekly >=1-day CHECK
--     (recurring_unit != 'weekly' OR sun OR mon OR tue OR wed OR thu OR fri
--     OR sat) involves all 7 weekday booleans
-- Per the ALTER TABLE docs: "Indexes and table constraints involving the
-- column will be automatically dropped as well." CASCADE is only required
-- for a column referenced by a view or another table's FK -- neither applies
-- here once the view above is gone (nothing else references
-- gym_class_schedules by FK).
ALTER TABLE gym_class_schedules
    DROP COLUMN class_time,
    DROP COLUMN sun,
    DROP COLUMN mon,
    DROP COLUMN tue,
    DROP COLUMN wed,
    DROP COLUMN thu,
    DROP COLUMN fri,
    DROP COLUMN sat,
    DROP COLUMN sun_instructor_id,
    DROP COLUMN mon_instructor_id,
    DROP COLUMN tue_instructor_id,
    DROP COLUMN wed_instructor_id,
    DROP COLUMN thu_instructor_id,
    DROP COLUMN fri_instructor_id,
    DROP COLUMN sat_instructor_id;

-- gym_class_schedules was emptied in step 0, so this NOT NULL column needs
-- no default/backfill.
ALTER TABLE gym_class_schedules
    ADD COLUMN weekday_slots JSONB NOT NULL
        CONSTRAINT chk_class_schedule_slots_shape
        CHECK (jsonb_typeof(weekday_slots) = 'object'
               AND weekday_slots <> '{}'::jsonb);

-- Recreate exactly as declared in schemas/gym_class_schedules.sql, with
-- security_invoker preserved.
CREATE VIEW gym_class_schedules_current
WITH (security_invoker = true) AS
SELECT DISTINCT ON (class_id) *
FROM gym_class_schedules
ORDER BY class_id, effective_from DESC, schedule_id DESC;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE
-- VIEW (see e.g. 20260622233351_remove_discount_mode.sql).
ALTER VIEW gym_class_schedules_current SET (security_invoker = true);

-- DROP VIEW drops all grants; re-apply exactly as originally granted in
-- 20260701020000_versioned_class_schedules.sql.
GRANT SELECT ON gym_class_schedules_current TO anon, authenticated, service_role;

-- ============================================================
-- 2. member_attendance: widen the occurrence key to include original_time
--    (mirrors schemas/member_attendance.sql). The original_time column
--    already exists (added by 20260701020000_versioned_class_schedules.sql);
--    only the UNIQUE constraint and index widen.
-- ============================================================

ALTER TABLE member_attendance
    DROP CONSTRAINT uq_attendance_member_occurrence;

ALTER TABLE member_attendance
    ADD CONSTRAINT uq_attendance_member_occurrence
        UNIQUE (member_id, class_id, original_date, original_time);

DROP INDEX idx_member_attendance_class_occurrence;

CREATE INDEX idx_member_attendance_class_occurrence
    ON member_attendance (class_id, original_date, original_time);

-- ============================================================
-- 3. class_signups: widen the occurrence key to include original_time
--    (mirrors schemas/class_signups.sql). The original_time column already
--    exists (added by 20260701020000_versioned_class_schedules.sql); only
--    the UNIQUE constraint and index widen.
-- ============================================================

ALTER TABLE class_signups
    DROP CONSTRAINT uq_class_signup_member_occurrence;

ALTER TABLE class_signups
    ADD CONSTRAINT uq_class_signup_member_occurrence
        UNIQUE (class_id, member_id, original_date, original_time);

DROP INDEX idx_class_signups_class_occurrence;

CREATE INDEX idx_class_signups_class_occurrence
    ON class_signups (class_id, original_date, original_time);

-- ============================================================
-- 4. class_instance_exceptions: gains original_time; UNIQUE (class_id,
--    original_date) -> UNIQUE (class_id, original_date, original_time)
--    (mirrors schemas/class_instance_exceptions.sql -- an exception now
--    binds to exactly ONE original slot, so two same-day occurrences of one
--    class can be overridden independently).
-- ============================================================

-- class_instance_exceptions was emptied in step 0, so this NOT NULL column
-- needs no default/backfill.
ALTER TABLE class_instance_exceptions
    ADD COLUMN original_time TIME NOT NULL;

-- The old UNIQUE (class_id, original_date) was declared without a CONSTRAINT
-- name (schemas/class_instance_exceptions.sql still declares its replacement
-- unnamed), so Postgres auto-named it. Rather than hardcode the guessed
-- auto-name, look it up by its exact column signature (contype = 'u', conkey
-- matching [class_id, original_date] in declared order) and drop whatever
-- it's actually called -- this can't silently miss due to a naming-scheme
-- assumption being wrong, which matters here: if the old 2-column constraint
-- were left behind, it would keep blocking the multi-slot-per-day exceptions
-- weekday_slots explicitly allows.
DO $$
DECLARE
    v_conname text;
    v_class_id_attnum smallint;
    v_original_date_attnum smallint;
BEGIN
    SELECT attnum INTO v_class_id_attnum
        FROM pg_attribute
        WHERE attrelid = 'class_instance_exceptions'::regclass
          AND attname = 'class_id';

    SELECT attnum INTO v_original_date_attnum
        FROM pg_attribute
        WHERE attrelid = 'class_instance_exceptions'::regclass
          AND attname = 'original_date';

    SELECT conname INTO v_conname
        FROM pg_constraint
        WHERE conrelid = 'class_instance_exceptions'::regclass
          AND contype = 'u'
          AND conkey = ARRAY[v_class_id_attnum, v_original_date_attnum]::smallint[];

    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE class_instance_exceptions DROP CONSTRAINT %I', v_conname);
    END IF;
END $$;

-- New key, unnamed to match schemas/class_instance_exceptions.sql (Postgres
-- auto-names it, same as the constraint just dropped).
ALTER TABLE class_instance_exceptions
    ADD UNIQUE (class_id, original_date, original_time);

-- original_time is occurrence-identity key material exactly like
-- original_date — lock it from authenticated UPDATEs (mirrors
-- access_rules/class_instance_exceptions.sql).
REVOKE UPDATE (original_time)
    ON TABLE class_instance_exceptions FROM authenticated;
