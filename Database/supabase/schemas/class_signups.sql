-- A member's reservation for a future (or past) class occurrence. A sign-up is
-- NOT attendance -- member_attendance is still only written by a check-in.
-- Capacity is reserving: an occurrence's room is "full" once the DISTINCT count
-- of members who are signed-up OR attended reaches the class's effective
-- max_capacity (gym_classes.max_capacity, overridden per-occurrence by
-- class_instance_exceptions.new_max_capacity) -- see
-- FastApiBackend/src/checkin/sql/signup_capacity_count.sql, the shared union
-- query the sign-up create path and the check-in capacity gate both use.
CREATE TABLE class_signups (
    signup_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_class_signup_gym REFERENCES gyms(gym_id),
    class_id UUID NOT NULL CONSTRAINT fk_class_signup_class_id REFERENCES gym_classes(class_id),
    member_id UUID NOT NULL,
    -- The gym-local calendar date of the occurrence being reserved (mirrors
    -- how the check-in API addresses an occurrence by class_id + occurrence_date
    -- rather than a materialized class_history row -- a sign-up can be created
    -- for a future occurrence that has no class_history row yet).
    occurrence_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (signup_id),
    -- One sign-up per member per occurrence; the idempotent create path relies
    -- on this exact constraint (ON CONFLICT (class_id, member_id, occurrence_date)).
    UNIQUE (class_id, member_id, occurrence_date),
    CONSTRAINT fk_class_signup_class
        FOREIGN KEY (class_id, gym_id)
        REFERENCES gym_classes (class_id, gym_id),
    CONSTRAINT fk_class_signup_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);

CREATE INDEX idx_class_signups_class_occurrence
    ON class_signups (class_id, occurrence_date);

CREATE INDEX idx_class_signups_member_gym
    ON class_signups (member_id, gym_id);
