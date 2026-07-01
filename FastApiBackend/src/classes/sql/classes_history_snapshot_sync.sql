-- Re-date a KEPT (today / past) rescheduled occurrence's materialized history
-- onto the new day + effective start time (and duration, if the override changed
-- it). The member_attendance rows keep their class_history_id, so they now
-- render on the new date's roster with no attendance rewrite. Runs at
-- service_role: class_history is append-only (REVOKE UPDATE for authenticated),
-- and occurred_at's immutable-columns entry guards only client-facing update
-- endpoints, not this internal service write. Keyed by class_history_id.
UPDATE class_history
SET occurred_at = CAST(:occurred_at AS TIMESTAMPTZ),
    duration_minutes = :duration_minutes
WHERE class_history_id = CAST(:class_history_id AS UUID)
