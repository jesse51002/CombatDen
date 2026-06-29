-- Mark the occurrence cancelled (un-occur) so it never re-materializes.
-- Idempotent on (class_id, original_date). Cancelling clears any reschedule
-- target (new_date = NULL): the occurrence is gone, not moved -- so cancelling
-- a previously-rescheduled occurrence leaves an unambiguous cancelled row on
-- the original date.
INSERT INTO class_instance_exceptions (
    class_id,
    gym_id,
    original_date,
    is_cancelled
)
VALUES (
    CAST(:class_id AS UUID),
    CAST(:gym_id AS UUID),
    :original_date,
    TRUE
)
ON CONFLICT (class_id, original_date) DO UPDATE SET
    is_cancelled = TRUE,
    new_date = NULL
RETURNING exception_id
