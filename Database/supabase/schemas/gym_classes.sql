-- The IDENTITY of a class: what it is, who may attend, what it's worth.
-- The recurring-schedule shape (time, duration, recurrence, weekday slots,
-- instructors, recurrence range) lives in gym_class_schedules as append-only
-- versioned rows — see gym_class_schedules.sql. Identity fields apply across
-- all versions (a rename renames the past too); schedule facts are versioned
-- so the past always re-renders identically.
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
    -- Every class HAS an image (the card/board/check-in UI leans on it):
    -- writers that receive none fill in the platform default (a generic
    -- people-in-a-gym photo — settings.default_class_image_url in the
    -- backend), so NULL never reaches the row.
    image_url VARCHAR NOT NULL,
    points_worth INTEGER NOT NULL DEFAULT 50 CHECK (points_worth > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (class_id),
    UNIQUE (class_id, gym_id)
);
