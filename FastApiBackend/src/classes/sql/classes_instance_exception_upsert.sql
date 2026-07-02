-- Upsert the single-slot override for one occurrence. The UNIQUE (class_id,
-- original_date, original_time) constraint makes this idempotent: a second
-- upsert for the same slot overwrites the prior override in place, and two
-- same-day occurrences hold independent rows.
INSERT INTO class_instance_exceptions (
    class_id,
    gym_id,
    original_date,
    original_time,
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_max_capacity,
    new_instructor_id,
    new_date
)
VALUES (
    :class_id,
    :gym_id,
    :original_date,
    :original_time,
    :is_cancelled,
    :new_class_time,
    :new_duration_minutes,
    :new_max_capacity,
    :new_instructor_id,
    :new_date
)
ON CONFLICT (class_id, original_date, original_time) DO UPDATE SET
    is_cancelled = EXCLUDED.is_cancelled,
    new_class_time = EXCLUDED.new_class_time,
    new_duration_minutes = EXCLUDED.new_duration_minutes,
    new_max_capacity = EXCLUDED.new_max_capacity,
    new_instructor_id = EXCLUDED.new_instructor_id,
    new_date = EXCLUDED.new_date
RETURNING
    exception_id,
    class_id,
    gym_id,
    original_date,
    original_time,
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_max_capacity,
    new_instructor_id,
    new_date,
    created_at
