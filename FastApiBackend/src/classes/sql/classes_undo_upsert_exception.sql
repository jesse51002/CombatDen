-- Mark the occurrence cancelled (un-occur). Idempotent on
-- (class_id, original_date, original_time) -- the exact slot; a same-day
-- sibling occurrence's exception row is untouched. Cancelling clears any
-- reschedule target (new_date = NULL): the occurrence is gone, not moved --
-- so cancelling a previously-rescheduled occurrence leaves an unambiguous
-- cancelled row on the original slot.
INSERT INTO class_instance_exceptions (
    class_id,
    gym_id,
    original_date,
    original_time,
    is_cancelled
)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    :original_date,
    :original_time,
    TRUE
)
ON CONFLICT (class_id, original_date, original_time) DO UPDATE SET
    is_cancelled = TRUE,
    new_date = NULL
RETURNING exception_id
