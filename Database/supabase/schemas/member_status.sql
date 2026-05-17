-- Append-mostly log of a member's account-state periods.
-- Stored statuses: 'trial', 'full', 'disabled'. There is no stored
-- 'inactive' — that's derived from absence of coverage today.
--   trial    = probationary trial window
--   full     = full / converted member (membership tier, NOT class-engagement)
--   disabled = explicitly banned / suspended by the gym (distinct from
--              merely lapsed; lapsed members are 'inactive' by default)
--
-- "active" / "inactive" terminology is reserved for class-attendance
-- engagement, computed elsewhere — not membership tier. That's why the
-- full-member tier is `full`, not `active`.
--
-- The gist EXCLUDE constraint forbids overlapping periods per member, so
-- a member is never simultaneously in trial and full, and never in two
-- trials. Inclusive bounds (`[]`) on daterange mean a new period must
-- start on or after the day AFTER the previous period's end_date.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE member_status_type AS ENUM ('trial', 'full', 'disabled');

CREATE TABLE member_status (
    status_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_member_status_gym REFERENCES gyms(gym_id),
    status_type member_status_type NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (status_id),
    CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT fk_member_status_member
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    EXCLUDE USING gist (
        member_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
);

CREATE INDEX idx_member_status_member_current
    ON member_status (member_id, start_date DESC);
