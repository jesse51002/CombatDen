-- Reschedule an occurrence: move the exact (original_date, original_time)
-- slot to new_date (any date -- past, today, or future; no lower bound). On
-- conflict ONLY new_date + is_cancelled are touched, preserving any existing
-- time / duration / capacity / instructor override already on that occurrence
-- (a plain override upsert would wipe them). is_cancelled is forced FALSE so
-- rescheduling a previously-cancelled occurrence revives it at the new date.
INSERT INTO class_instance_exceptions (
    class_id,
    gym_id,
    original_date,
    original_time,
    new_date,
    is_cancelled
)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    :original_date,
    :original_time,
    :new_date,
    FALSE
)
ON CONFLICT (class_id, original_date, original_time) DO UPDATE SET
    new_date = EXCLUDED.new_date,
    is_cancelled = FALSE
RETURNING exception_id, class_id, original_date, original_time, new_date
