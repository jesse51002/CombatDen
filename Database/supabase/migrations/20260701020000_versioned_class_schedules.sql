-- Hand-authored migration.
-- Versioned class schedules replace class_history + the embedded-recurrence
-- gym_classes shape: the recurring-schedule facts (time, duration, recurrence,
-- weekday slots, instructors, recurrence range) move off gym_classes onto a
-- new append-only versioned table, gym_class_schedules (mirroring
-- membership_plans -> membership_plan_prices). gym_classes becomes
-- identity-only. class_history is retired entirely -- occurrences are now
-- identified by their ORIGINAL slot (class_id, original_date, original_time)
-- directly on member_attendance / class_signups instead of a materialized
-- history row.
--
-- This is a DESTRUCTIVE, dev-only rebuild of the class tables: gym_classes,
-- gym_class_schedules (new), class_instance_exceptions, class_range_exceptions,
-- class_signups, member_attendance, and class_history are dropped and
-- recreated to reach the schemas/ end state. No data migration -- the data is
-- disposable dev/demo content, re-seeded after this runs.
--
-- Drop order (FK-safe, explicit -- no blanket CASCADE):
--   member_attendance, class_signups, class_instance_exceptions,
--   class_range_exceptions, class_history, then gym_classes, then the
--   recurring_unit enum (previously owned by gym_classes).
-- Create order: recurring_unit (now owned by gym_class_schedules), gym_classes
-- (identity-only), gym_class_schedules (+ indexes + the
-- gym_class_schedules_current view), class_instance_exceptions,
-- class_range_exceptions, class_signups, member_attendance -- each re-applying
-- its access_rules/ policies immediately after create, since dropping a table
-- drops its RLS policies.

-- ============================================================
-- Drop, in FK-safe order
-- ============================================================

DROP TABLE member_attendance;
DROP TABLE class_signups;
DROP TABLE class_instance_exceptions;
DROP TABLE class_range_exceptions;
DROP TABLE class_history;
DROP TABLE gym_classes;

DROP TYPE recurring_unit;

-- ============================================================
-- recurring_unit (now owned by gym_class_schedules.sql)
-- ============================================================

CREATE TYPE recurring_unit AS ENUM ('daily', 'weekly', 'monthly');

-- ============================================================
-- gym_classes (identity-only; mirrors schemas/gym_classes.sql)
-- ============================================================

CREATE TABLE gym_classes (
    class_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_gym REFERENCES gyms(gym_id),
    class_name VARCHAR NOT NULL CHECK (class_name <> ''),
    class_description VARCHAR,
    -- JSONB array of plan_id strings allowed to attend this class.
    -- NULL = all plans allowed (used by the check-in eligibility gate).
    allowed_plan_ids JSONB,
    -- Room capacity is identity, not schedule shape: it is gated at
    -- check-in/sign-up time ("now"), never snapshotted per occurrence, and
    -- per-occurrence overrides live on class_instance_exceptions.
    max_capacity INTEGER CHECK (max_capacity > 0),
    image_url VARCHAR,
    points_worth INTEGER NOT NULL DEFAULT 50 CHECK (points_worth > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (class_id),
    UNIQUE (class_id, gym_id)
);

-- Access rules for gym_classes (mirrors access_rules/gym_classes.sql)
-- DROP TABLE destroyed the original role grants; restore the standard
-- Supabase posture before the policies/REVOKEs below pare authenticated
-- back down (same pattern as prior recreate migrations).
GRANT ALL ON TABLE gym_classes TO anon, authenticated, service_role;

ALTER TABLE gym_classes ENABLE ROW LEVEL SECURITY;

-- All employees can view classes for their gym
CREATE POLICY "Gym employees can view classes"
    ON gym_classes
    FOR SELECT
    USING (is_gym_employee(gym_classes.gym_id));

-- Members can view classes for their gym
CREATE POLICY "Members can view classes"
    ON gym_classes
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_classes.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- Gym staff can insert classes
CREATE POLICY "Gym staff can insert classes"
    ON gym_classes
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_classes.gym_id));

-- Gym staff can update classes
CREATE POLICY "Gym staff can update classes"
    ON gym_classes
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_classes.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_classes.gym_id));

-- Identity / structural columns stay immutable
REVOKE UPDATE (class_id, gym_id, created_at) ON TABLE gym_classes FROM authenticated;

-- ============================================================
-- gym_class_schedules (new; mirrors schemas/gym_class_schedules.sql)
-- ============================================================

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

-- Access rules for gym_class_schedules (mirrors access_rules/gym_class_schedules.sql)
GRANT ALL ON TABLE gym_class_schedules TO anon, authenticated, service_role;
GRANT SELECT ON gym_class_schedules_current TO anon, authenticated, service_role;

ALTER TABLE gym_class_schedules ENABLE ROW LEVEL SECURITY;

-- Read posture mirrors gym_classes: staff see their gym's schedule versions,
-- members see their gym's (the mobile app renders the schedule).
CREATE POLICY "Gym employees can view class schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (is_gym_employee(gym_class_schedules.gym_id));

CREATE POLICY "Members can view class schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_class_schedules.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- Append-only versioned rows, written by the service-role backend ONLY.
-- Minting a version runs inside one backend transaction with the
-- version-change wipe (sign-up deletion + check-in reversal + points
-- clawback) -- a raw client INSERT would bypass exactly that billing-adjacent
-- logic, the same argument that gates membership_plan_prices /
-- gym_discount_values. No authenticated write path at all; versions are
-- never UPDATE'd or DELETE'd by anyone (write-once rows).
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_class_schedules FROM authenticated;

-- ============================================================
-- class_instance_exceptions (unchanged shape; mirrors
-- schemas/class_instance_exceptions.sql -- new_date has NO future-only CHECK,
-- per 20260701000000_class_signups_and_anydate_reschedule.sql)
-- ============================================================

CREATE TABLE class_instance_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_instance_exception_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_instance_exception_gym REFERENCES gyms(gym_id),
    original_date DATE NOT NULL,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    new_class_time TIME,
    new_duration_minutes INTEGER CHECK (new_duration_minutes IS NULL OR new_duration_minutes > 0),
    new_max_capacity INTEGER CHECK (new_max_capacity IS NULL OR new_max_capacity > 0),
    new_instructor_id UUID,
    -- Reschedule target: when set, this occurrence is moved off original_date to
    -- new_date (the expander suppresses original_date and emits at new_date). NULL =
    -- not rescheduled. new_date may be any date -- past, today, or future: the
    -- original_date is only the anchor the move is measured from, not a lower bound.
    new_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exception_id),
    UNIQUE (class_id, original_date),
    CONSTRAINT fk_instance_exception_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_instance_exception_instructor
        FOREIGN KEY (new_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);

-- Access rules for class_instance_exceptions (mirrors
-- access_rules/class_instance_exceptions.sql)
GRANT ALL ON TABLE class_instance_exceptions TO anon, authenticated, service_role;

ALTER TABLE class_instance_exceptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view instance exceptions"
    ON class_instance_exceptions
    FOR SELECT
    USING (is_gym_employee(class_instance_exceptions.gym_id));

CREATE POLICY "Members can view instance exceptions"
    ON class_instance_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_instance_exceptions.gym_id
            AND members.user_id = auth.uid()
        )
    );

CREATE POLICY "Gym staff can insert instance exceptions"
    ON class_instance_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(class_instance_exceptions.gym_id));

CREATE POLICY "Gym staff can update instance exceptions"
    ON class_instance_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(class_instance_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(class_instance_exceptions.gym_id));

REVOKE UPDATE (exception_id, class_id, gym_id, original_date, created_at)
    ON TABLE class_instance_exceptions FROM authenticated;

-- ============================================================
-- class_range_exceptions (unchanged shape; mirrors
-- schemas/class_range_exceptions.sql)
-- ============================================================

CREATE TABLE class_range_exceptions (
    exception_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    class_id UUID NOT NULL CONSTRAINT fk_range_exception_class_id REFERENCES gym_classes(class_id),
    gym_id UUID NOT NULL CONSTRAINT fk_range_exception_gym REFERENCES gyms(gym_id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    new_instructor_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (exception_id),
    CHECK (end_date >= start_date),
    CHECK (is_cancelled OR new_instructor_id IS NOT NULL),
    CONSTRAINT fk_range_exception_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_range_exception_instructor
        FOREIGN KEY (new_instructor_id, gym_id)
        REFERENCES gym_employees (employee_id, gym_id)
);

-- Access rules for class_range_exceptions (mirrors
-- access_rules/class_range_exceptions.sql)
GRANT ALL ON TABLE class_range_exceptions TO anon, authenticated, service_role;

ALTER TABLE class_range_exceptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view range exceptions"
    ON class_range_exceptions
    FOR SELECT
    USING (is_gym_employee(class_range_exceptions.gym_id));

CREATE POLICY "Members can view range exceptions"
    ON class_range_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_range_exceptions.gym_id
            AND members.user_id = auth.uid()
        )
    );

CREATE POLICY "Gym staff can insert range exceptions"
    ON class_range_exceptions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(class_range_exceptions.gym_id));

CREATE POLICY "Gym staff can update range exceptions"
    ON class_range_exceptions
    FOR UPDATE
    USING (is_gym_admin_or_owner(class_range_exceptions.gym_id))
    WITH CHECK (is_gym_admin_or_owner(class_range_exceptions.gym_id));

REVOKE UPDATE (exception_id, class_id, gym_id, created_at)
    ON TABLE class_range_exceptions FROM authenticated;

-- ============================================================
-- class_signups (mirrors schemas/class_signups.sql -- occurrence_date
-- renamed original_date, original_time added, UNIQUE constraint renamed)
-- ============================================================

CREATE TABLE class_signups (
    signup_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_signup_gym REFERENCES gyms(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_class_signup_class_id REFERENCES gym_classes(class_id),
    member_id UUID NOT NULL,
    -- Occurrence identity: the owning schedule version's original slot
    -- (stamped from the resolved slot at create).
    original_date DATE NOT NULL,
    original_time TIME NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (signup_id),
    -- One sign-up per member per original occurrence; the idempotent create
    -- path relies on this exact constraint (ON CONFLICT (class_id, member_id,
    -- original_date)). Date alone disambiguates because a class has at most
    -- ONE original occurrence per gym-local date (the one-per-day invariant);
    -- original_time is stored for the version-change exact-slot match.
    CONSTRAINT uq_class_signup_member_occurrence
        UNIQUE (class_id, member_id, original_date),
    CONSTRAINT fk_class_signup_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_signup_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_class_signups_class_occurrence
    ON class_signups (class_id, original_date);

CREATE INDEX idx_class_signups_member_gym
    ON class_signups (member_id, gym_id);

-- Access rules for class_signups (mirrors access_rules/class_signups.sql)
GRANT ALL ON TABLE class_signups TO anon, authenticated, service_role;

ALTER TABLE class_signups ENABLE ROW LEVEL SECURITY;

-- Members can read their own sign-ups; gym staff can read everything at their
-- gym. Mirrors member_attendance's SELECT policy shape.
CREATE POLICY "Users and gym staff can view class signups"
    ON class_signups
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = class_signups.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(class_signups.gym_id)
    );

-- Both staff and the member themselves may create / cancel a sign-up, but
-- that authorization (staff-for-any-gym-member OR member-for-self) is
-- enforced by the API's verify_can_view_member check, not by RLS --
-- class_signups has NO authenticated write policy at all: every write goes
-- through the backend's service_role connection.
REVOKE INSERT, UPDATE, DELETE ON TABLE class_signups FROM authenticated;

-- ============================================================
-- member_attendance (mirrors schemas/member_attendance.sql --
-- class_history_id dropped; now class_id + original_date + original_time +
-- occurred_at)
-- ============================================================

CREATE TABLE member_attendance (
    log_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_attendance_gym REFERENCES gyms(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_attendance_class_id REFERENCES gym_classes(class_id),
    -- Occurrence identity: the owning schedule version's original slot.
    original_date DATE NOT NULL,
    original_time TIME NOT NULL,
    -- Denormalized EFFECTIVE start instant (exceptions applied), written at
    -- check-in and re-synced by the two paths that re-time a kept occurrence
    -- (same-date override on an attended occurrence; reschedule-to-today/past).
    -- Consumed ONLY by time-window SQL (streak / cycle counts / last_class);
    -- identity joins always use (class_id, original_date).
    occurred_at TIMESTAMPTZ NOT NULL,
    -- The membership row + plan that covered this check-in (billing attribution);
    -- NULL together when an admin check-in had no covering membership to attribute to.
    plan_id UUID,
    item_id UUID,
    PRIMARY KEY (log_id),
    -- Idempotency anchor: one attendance row per member per original
    -- occurrence. A class has at most ONE original occurrence per gym-local
    -- date (the one-per-day invariant), so date alone disambiguates;
    -- original_time is stored for the version-change exact-slot match, not
    -- for uniqueness.
    CONSTRAINT uq_attendance_member_occurrence
        UNIQUE (member_id, class_id, original_date),
    CONSTRAINT chk_attendance_membership_pair
        CHECK ((plan_id IS NULL) = (item_id IS NULL)),
    CONSTRAINT fk_attendance_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_attendance_class_gym
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_attendance_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans_unfiltered (plan_id, gym_id),
    CONSTRAINT fk_attendance_membership_member
        FOREIGN KEY (item_id, member_id)
        REFERENCES member_memberships_unfiltered (item_id, member_id)
);

CREATE INDEX idx_member_attendance_member_gym
    ON member_attendance (member_id, gym_id);

CREATE INDEX idx_member_attendance_class_occurrence
    ON member_attendance (class_id, original_date);

CREATE INDEX idx_member_attendance_member_occurred
    ON member_attendance (member_id, occurred_at DESC);

-- Access rules for member_attendance (mirrors access_rules/member_attendance.sql)
GRANT ALL ON TABLE member_attendance TO anon, authenticated, service_role;

ALTER TABLE member_attendance ENABLE ROW LEVEL SECURITY;

-- Members can read their own attendance; gym staff can read everything at their gym
CREATE POLICY "Users and gym staff can view attendance"
    ON member_attendance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_attendance.member_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(member_attendance.gym_id)
    );

-- Append-only AND written by the service-role backend ONLY (the check-in gate).
-- No authenticated write path at all: staff never insert attendance directly —
-- every write goes through the gated check-in endpoint, so a raw client INSERT
-- can't bypass the eligibility / capacity / points / billing-attribution logic.
REVOKE INSERT, UPDATE, DELETE ON TABLE member_attendance FROM authenticated;
