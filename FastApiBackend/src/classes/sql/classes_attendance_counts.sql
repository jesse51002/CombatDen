-- Recorded attendance per materialized occurrence, keyed by (class_id,
-- occurred_at) -- the same idempotency anchor the expander's occurred_at lands
-- on. occurred_at is bounded to a UTC range (computed in the service with a day
-- of slack on each side) so the scan stays cheap; the reader maps rows back to
-- occurrences by exact (class_id, occurred_at) match.
SELECT
    ch.class_id,
    ch.occurred_at,
    COUNT(ma.log_id) AS attendance_count
FROM class_history ch
LEFT JOIN member_attendance ma
    ON ma.class_history_id = ch.class_history_id
WHERE ch.gym_id = :gym_id
  AND ch.occurred_at >= :lower
  AND ch.occurred_at <= :upper
GROUP BY ch.class_id, ch.occurred_at
