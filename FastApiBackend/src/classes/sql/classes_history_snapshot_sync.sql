-- Sync a MATERIALIZED occurrence's class_history snapshot onto its current
-- effective values. Called on ANY edit of an already-materialized occurrence:
-- a same-date override (retime / re-instructor / re-duration) and a
-- today/past reschedule's keep-path both call this, so the "immutable" past
-- board (classes_board_past_history.sql) always renders what was actually
-- edited, not stale pre-edit values. The member_attendance rows keep their
-- class_history_id, so they follow onto the new occurred_at / instructor /
-- duration with no attendance rewrite. Runs at service_role: class_history is
-- append-only (REVOKE UPDATE for authenticated), and each of these columns'
-- immutable-columns entry guards only client-facing update endpoints, not
-- this internal service write. Keyed by class_history_id.
UPDATE class_history
SET occurred_at = CAST(:occurred_at AS TIMESTAMPTZ),
    duration_minutes = :duration_minutes,
    instructor_id = CAST(:instructor_id AS UUID)
WHERE class_history_id = CAST(:class_history_id AS UUID)
