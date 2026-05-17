-- Append-mostly log of a member's class-engagement state (active / inactive).
-- Distinct axis from member_status: a member can be account-tier "full"
-- but engagement-state "inactive" if they haven't shown up to class.
--
-- Same shape as member_status, including the gist EXCLUDE that prevents
-- overlapping periods per member. Inclusive bounds (`[]`) on daterange
-- mean a new period must start on or after the day AFTER the previous
-- period's end_date.
--
-- The view exposes the current period as a boolean `active`. Absence of
-- any covering row → active = false.
CREATE TYPE member_active_type AS ENUM ('active', 'inactive');

CREATE TABLE member_active (
    active_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_member_active_gym REFERENCES gyms(gym_id),
    active_type member_active_type NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (active_id),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT fk_member_active_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    EXCLUDE USING gist (
        member_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
);

CREATE INDEX idx_member_active_member_current
    ON member_active (member_id, start_date DESC);
