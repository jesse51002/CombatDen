-- A member's reservation for a class occurrence. A sign-up is NOT attendance
-- -- member_attendance is still only written by a check-in.
--
-- An occurrence is identified by its ORIGINAL slot -- (class_id,
-- original_date, original_time), the date + time the OWNING schedule version
-- (gym_class_schedules) defines BEFORE exceptions, gym-local wall clock. A
-- reschedule / retime exception never re-keys the occurrence, so sign-ups
-- carry across single-occurrence moves automatically. When a NEW schedule
-- VERSION is minted, sign-ups whose original slot no longer exists under the
-- new version are wiped (exact wall-clock match survives) -- see
-- FastApiBackend/src/classes/service/classes_versions_service.py.
--
-- Capacity is reserving: an occurrence's room is "full" once the DISTINCT
-- count of members who are signed-up OR attended reaches the class's
-- effective max_capacity (gym_classes.max_capacity, overridden per-occurrence
-- by class_instance_exceptions.new_max_capacity) -- see
-- FastApiBackend/src/checkin/sql/signup_capacity_count.sql, the shared union
-- query the sign-up create path and the check-in capacity gate both use.
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
    -- original_date, original_time)). A class may occur SEVERAL times on one
    -- gym-local date (weekday_slots holds a slot list per day), so the key is
    -- the full original slot — date AND time.
    CONSTRAINT uq_class_signup_member_occurrence
        UNIQUE (class_id, member_id, original_date, original_time),
    CONSTRAINT fk_class_signup_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_signup_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_class_signups_class_occurrence
    ON class_signups (class_id, original_date, original_time);

CREATE INDEX idx_class_signups_member_gym
    ON class_signups (member_id, gym_id);
