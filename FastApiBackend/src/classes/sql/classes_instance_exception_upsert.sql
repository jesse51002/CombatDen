-- Upsert the single-date override for one occurrence. The UNIQUE (class_id,
-- original_date) constraint makes this idempotent: a second upsert for the same
-- date overwrites the prior override in place.
INSERT INTO class_instance_exceptions (
    class_id,
    gym_id,
    original_date,
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
    :is_cancelled,
    :new_class_time,
    :new_duration_minutes,
    :new_max_capacity,
    :new_instructor_id,
    :new_date
)
ON CONFLICT (class_id, original_date) DO UPDATE SET
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
    is_cancelled,
    new_class_time,
    new_duration_minutes,
    new_max_capacity,
    new_instructor_id,
    new_date,
    created_at
